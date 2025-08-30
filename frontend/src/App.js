import React, { useState, useEffect } from 'react';
import './App.css';
import AuthForm from './AuthForm';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:4000';

function App() {
  const [user, setUser] = useState(null);
  const [token, setToken] = useState(null);
  const [tasks, setTasks] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [newTask, setNewTask] = useState({ title: '', description: '' });
  const [showForm, setShowForm] = useState(false);
  const [authLoading, setAuthLoading] = useState(true);

  // Verificar si hay token guardado al cargar la app
  useEffect(() => {
    const savedToken = localStorage.getItem('token');
    const savedUser = localStorage.getItem('user');
    
    if (savedToken && savedUser) {
      setToken(savedToken);
      setUser(JSON.parse(savedUser));
      // Verificar que el token sigue siendo válido
      verifyToken(savedToken);
    } else {
      setAuthLoading(false);
    }
  }, []);

  // Cargar tareas cuando el usuario se autentica
  useEffect(() => {
    if (user && token) {
      fetchTasks();
    }
  }, [user, token]);

  // Verificar validez del token
  const verifyToken = async (tokenToVerify) => {
    try {
      const response = await fetch(`${API_BASE_URL}/api/auth/me`, {
        headers: {
          'Authorization': `Bearer ${tokenToVerify}`
        }
      });

      if (response.ok) {
        const data = await response.json();
        setUser(data.data.user);
        setToken(tokenToVerify);
      } else {
        // Token inválido, limpiar datos
        handleLogout();
      }
    } catch (err) {
      console.error('Error verificando token:', err);
      handleLogout();
    } finally {
      setAuthLoading(false);
    }
  };

  // Función para manejar login exitoso
  const handleLogin = (userData, userToken) => {
    setUser(userData);
    setToken(userToken);
    setAuthLoading(false);
  };

  // Función para logout
  const handleLogout = () => {
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    setUser(null);
    setToken(null);
    setTasks([]);
    setAuthLoading(false);
  };

  // Función para hacer requests autenticados
  const authenticatedFetch = async (url, options = {}) => {
    const response = await fetch(url, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
        ...options.headers,
      },
    });

    if (response.status === 401 || response.status === 403) {
      // Token expirado o inválido
      handleLogout();
      throw new Error('Sesión expirada');
    }

    return response;
  };

  // Función para obtener todas las tareas
  const fetchTasks = async () => {
    if (!token) return;
    
    setLoading(true);
    setError('');
    try {
      const response = await authenticatedFetch(`${API_BASE_URL}/api/tasks`);
      const data = await response.json();
      
      if (data.success) {
        setTasks(data.data);
      } else {
        setError('Error al cargar las tareas');
      }
    } catch (err) {
      if (err.message !== 'Sesión expirada') {
        setError('Error de conexión con el servidor');
        console.error('Error:', err);
      }
    } finally {
      setLoading(false);
    }
  };

  // Función para crear nueva tarea
  const createTask = async (e) => {
    e.preventDefault();
    if (!newTask.title.trim() || !newTask.description.trim()) {
      setError('Título y descripción son requeridos');
      return;
    }

    setLoading(true);
    setError('');
    
    try {
      const response = await authenticatedFetch(`${API_BASE_URL}/api/tasks`, {
        method: 'POST',
        body: JSON.stringify(newTask),
      });
      
      const data = await response.json();
      
      if (data.success) {
        setTasks([...tasks, data.data]);
        setNewTask({ title: '', description: '' });
        setShowForm(false);
      } else {
        setError(data.message || 'Error al crear la tarea');
      }
    } catch (err) {
      if (err.message !== 'Sesión expirada') {
        setError('Error de conexión con el servidor');
        console.error('Error:', err);
      }
    } finally {
      setLoading(false);
    }
  };

  // Función para cambiar estado de completado
  const toggleTask = async (taskId, completed) => {
    try {
      const response = await authenticatedFetch(`${API_BASE_URL}/api/tasks/${taskId}`, {
        method: 'PUT',
        body: JSON.stringify({ completed: !completed }),
      });
      
      const data = await response.json();
      
      if (data.success) {
        setTasks(tasks.map(task => 
          task.id === taskId ? { ...task, completed: !completed } : task
        ));
      } else {
        setError(data.message || 'Error al actualizar la tarea');
      }
    } catch (err) {
      if (err.message !== 'Sesión expirada') {
        setError('Error de conexión con el servidor');
        console.error('Error:', err);
      }
    }
  };

  // Función para eliminar tarea
  const deleteTask = async (taskId) => {
    if (!window.confirm('¿Estás seguro de que quieres eliminar esta tarea?')) {
      return;
    }

    try {
      const response = await authenticatedFetch(`${API_BASE_URL}/api/tasks/${taskId}`, {
        method: 'DELETE',
      });
      
      const data = await response.json();
      
      if (data.success) {
        setTasks(tasks.filter(task => task.id !== taskId));
      } else {
        setError(data.message || 'Error al eliminar la tarea');
      }
    } catch (err) {
      if (err.message !== 'Sesión expirada') {
        setError('Error de conexión con el servidor');
        console.error('Error:', err);
      }
    }
  };

  // Mostrar loading mientras se verifica autenticación
  if (authLoading) {
    return (
      <div className="auth-loading">
        <div className="spinner"></div>
        <p>Verificando sesión...</p>
      </div>
    );
  }

  // Si no está autenticado, mostrar formulario de login
  if (!user || !token) {
    return <AuthForm onLogin={handleLogin} />;
  }

  return (
    <div className="App">
      <header className="App-header">
        <div className="header-content">
          <div className="title-section">
            <h1>📋 Gestor de Tareas</h1>
            <p>Aplicación React + Node.js con Docker</p>
          </div>
          <div className="user-section">
            <div className="user-info">
              <span className="welcome-text">👋 Hola, <strong>{user.username}</strong></span>
              <span className="user-email">{user.email}</span>
            </div>
            <button onClick={handleLogout} className="logout-btn">
              🚪 Cerrar Sesión
            </button>
          </div>
        </div>
      </header>

      <main className="main-content">
        {/* Botón para mostrar/ocultar formulario */}
        <div className="actions">
          <button 
            className="btn-primary"
            onClick={() => setShowForm(!showForm)}
          >
            {showForm ? '✕ Cancelar' : '➕ Nueva Tarea'}
          </button>
        </div>

        {/* Formulario para nueva tarea */}
        {showForm && (
          <div className="task-form">
            <h3>Crear Nueva Tarea</h3>
            <form onSubmit={createTask}>
              <div className="form-group">
                <label>Título:</label>
                <input
                  type="text"
                  value={newTask.title}
                  onChange={(e) => setNewTask({ ...newTask, title: e.target.value })}
                  placeholder="Ingresa el título de la tarea"
                  required
                />
              </div>
              <div className="form-group">
                <label>Descripción:</label>
                <textarea
                  value={newTask.description}
                  onChange={(e) => setNewTask({ ...newTask, description: e.target.value })}
                  placeholder="Describe la tarea"
                  rows="3"
                  required
                />
              </div>
              <div className="form-actions">
                <button type="submit" className="btn-success" disabled={loading}>
                  {loading ? 'Creando...' : '✓ Crear Tarea'}
                </button>
              </div>
            </form>
          </div>
        )}

        {/* Mensajes de error */}
        {error && (
          <div className="error-message">
            ⚠️ {error}
            <button onClick={() => setError('')} className="close-btn">✕</button>
          </div>
        )}

        {/* Loading indicator */}
        {loading && !showForm && (
          <div className="loading">
            <div className="spinner"></div>
            <p>Cargando tareas...</p>
          </div>
        )}

        {/* Lista de tareas */}
        <div className="tasks-container">
          <div className="tasks-header">
            <h2>Mis Tareas ({tasks.length})</h2>
            <button onClick={fetchTasks} className="btn-secondary" disabled={loading}>
              🔄 Actualizar
            </button>
          </div>

          {tasks.length === 0 && !loading ? (
            <div className="empty-state">
              <p>📝 No hay tareas aún</p>
              <p>¡Crea tu primera tarea para comenzar!</p>
            </div>
          ) : (
            <div className="tasks-list">
              {tasks.map(task => (
                <div key={task.id} className={`task-card ${task.completed ? 'completed' : ''}`}>
                  <div className="task-content">
                    <div className="task-header">
                      <h3>{task.title}</h3>
                      <div className="task-actions">
                        <button
                          onClick={() => toggleTask(task.id, task.completed)}
                          className={`btn-toggle ${task.completed ? 'completed' : 'pending'}`}
                          title={task.completed ? 'Marcar como pendiente' : 'Marcar como completada'}
                        >
                          {task.completed ? '✓' : '○'}
                        </button>
                        <button
                          onClick={() => deleteTask(task.id)}
                          className="btn-delete"
                          title="Eliminar tarea"
                        >
                          🗑️
                        </button>
                      </div>
                    </div>
                    <p className="task-description">{task.description}</p>
                    <div className="task-meta">
                      <span className={`status ${task.completed ? 'completed' : 'pending'}`}>
                        {task.completed ? '✅ Completada' : '⏳ Pendiente'}
                      </span>
                      <span className="created-date">
                        📅 {new Date(task.createdAt).toLocaleDateString('es-ES')}
                      </span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </main>

      <footer className="App-footer">
        <p>🐳 Ejecutándose en contenedores Docker</p>
        <p>Backend: Node.js + Express | Frontend: React</p>
        <p>🔐 Autenticado como: {user.username}</p>
      </footer>
    </div>
  );
}

export default App;