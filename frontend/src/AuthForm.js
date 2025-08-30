import React, { useState } from 'react';
import './AuthForm.css';

const AuthForm = ({ onLogin }) => {
  const [isLogin, setIsLogin] = useState(true);
  const [formData, setFormData] = useState({
    username: '',
    email: '',
    password: ''
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:4000';

  const handleInputChange = (e) => {
    setFormData({
      ...formData,
      [e.target.name]: e.target.value
    });
    setError('');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      const endpoint = isLogin ? '/api/auth/login' : '/api/auth/register';
      const payload = isLogin 
        ? { username: formData.username, password: formData.password }
        : { username: formData.username, email: formData.email, password: formData.password };

      const response = await fetch(`${API_BASE_URL}${endpoint}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });

      const data = await response.json();

      if (data.success) {
        // Guardar token y datos del usuario
        localStorage.setItem('token', data.data.token);
        localStorage.setItem('user', JSON.stringify(data.data.user));
        
        // Llamar función de callback para actualizar estado en App
        onLogin(data.data.user, data.data.token);
      } else {
        setError(data.message || 'Error en la autenticación');
      }
    } catch (err) {
      setError('Error de conexión con el servidor');
      console.error('Error:', err);
    } finally {
      setLoading(false);
    }
  };

  const toggleMode = () => {
    setIsLogin(!isLogin);
    setError('');
    setFormData({
      username: '',
      email: '',
      password: ''
    });
  };

  return (
    <div className="auth-container">
      <div className="auth-card">
        <div className="auth-header">
          <h2>{isLogin ? '🔐 Iniciar Sesión' : '📝 Registrarse'}</h2>
          <p>Accede a tu gestor de tareas personalizado</p>
        </div>

        <form onSubmit={handleSubmit} className="auth-form">
          <div className="form-group">
            <label>Usuario:</label>
            <input
              type="text"
              name="username"
              value={formData.username}
              onChange={handleInputChange}
              placeholder={isLogin ? "Ingresa tu usuario" : "Elige un nombre de usuario"}
              required
            />
          </div>

          {!isLogin && (
            <div className="form-group">
              <label>Email:</label>
              <input
                type="email"
                name="email"
                value={formData.email}
                onChange={handleInputChange}
                placeholder="tu@email.com"
                required
              />
            </div>
          )}

          <div className="form-group">
            <label>Contraseña:</label>
            <input
              type="password"
              name="password"
              value={formData.password}
              onChange={handleInputChange}
              placeholder="Ingresa tu contraseña"
              required
            />
          </div>

          {error && (
            <div className="error-message">
              ⚠️ {error}
            </div>
          )}

          <div className="form-actions">
            <button type="submit" className="btn-primary" disabled={loading}>
              {loading ? (
                <>
                  <div className="spinner-small"></div>
                  {isLogin ? 'Iniciando sesión...' : 'Registrando...'}
                </>
              ) : (
                isLogin ? '🔑 Iniciar Sesión' : '✨ Registrarse'
              )}
            </button>
          </div>
        </form>

        <div className="auth-switch">
          <p>
            {isLogin ? '¿No tienes cuenta?' : '¿Ya tienes cuenta?'}
            <button 
              type="button" 
              onClick={toggleMode} 
              className="switch-btn"
              disabled={loading}
            >
              {isLogin ? 'Registrarse aquí' : 'Iniciar sesión aquí'}
            </button>
          </p>
        </div>

        {isLogin && (
          <div className="demo-credentials">
            <p><strong>👤 Usuarios de prueba:</strong></p>
            <div className="demo-user">
              <span>Admin: <code>admin / admin123</code></span>
            </div>
            <div className="demo-user">
              <span>Usuario: <code>usuario / admin123</code></span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default AuthForm;