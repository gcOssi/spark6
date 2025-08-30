const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

const app = express();
const PORT = process.env.PORT || 4000;
const JWT_SECRET = process.env.JWT_SECRET || 'tu_clave_secreta_super_segura_2024';

// Middleware
app.use(cors({
  origin: process.env.FRONTEND_URL || 'http://localhost:3000',
  credentials: true
}));
app.use(express.json());

// Base de datos en memoria para usuarios (en producción usarías una DB real)
let users = [
  {
    id: 1,
    username: 'admin',
    email: 'admin@ejemplo.com',
    password: '$2a$10$rOy8.2ZuK2G9zK9z7uJ./.mQ7HZ8KGK8HZ8KGK8HZ8KGK8HZ8KGK8u' // admin123
  },
  {
    id: 2,
    username: 'usuario',
    email: 'usuario@ejemplo.com', 
    password: '$2a$10$rOy8.2ZuK2G9zK9z7uJ./.mQ7HZ8KGK8HZ8KGK8HZ8KGK8HZ8KGK8u' // admin123
  }
];

// Función para inicializar usuarios con contraseñas hasheadas correctamente
const initializeUsers = async () => {
  try {
    const hashedPassword = await bcrypt.hash('admin123', 10);
    users[0].password = hashedPassword;
    users[1].password = hashedPassword;
    console.log('✅ Usuarios inicializados con contraseñas hasheadas');
  } catch (error) {
    console.error('Error inicializando usuarios:', error);
  }
};

// Inicializar usuarios al arrancar el servidor
initializeUsers();

// Datos de ejemplo en memoria (en producción usarías una base de datos)
let tasks = [
  { id: 1, title: 'Aprender Docker', description: 'Crear contenedores para apps', completed: false, createdAt: new Date().toISOString(), userId: 1 },
  { id: 2, title: 'Configurar Express', description: 'Crear API REST', completed: true, createdAt: new Date().toISOString(), userId: 1 },
  { id: 3, title: 'Conectar Frontend', description: 'Comunicar React con API', completed: false, createdAt: new Date().toISOString(), userId: 2 }
];

let nextId = 4;
let nextUserId = 3;

// Middleware para verificar JWT
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

  if (!token) {
    return res.status(401).json({
      success: false,
      message: 'Token de acceso requerido'
    });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({
        success: false,
        message: 'Token inválido o expirado'
      });
    }
    req.user = user;
    next();
  });
};

// Rutas de autenticación

// POST - Registro de usuario
app.post('/api/auth/register', async (req, res) => {
  try {
    const { username, email, password } = req.body;

    if (!username || !email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Todos los campos son requeridos'
      });
    }

    // Verificar si el usuario ya existe
    const existingUser = users.find(u => u.username === username || u.email === email);
    if (existingUser) {
      return res.status(400).json({
        success: false,
        message: 'El usuario o email ya existe'
      });
    }

    // Encriptar contraseña
    const hashedPassword = await bcrypt.hash(password, 10);

    // Crear nuevo usuario
    const newUser = {
      id: nextUserId++,
      username,
      email,
      password: hashedPassword
    };

    users.push(newUser);
    console.log('POST /api/auth/register - Usuario registrado:', username);

    // Crear token
    const token = jwt.sign(
      { 
        userId: newUser.id, 
        username: newUser.username,
        email: newUser.email
      },
      JWT_SECRET,
      { expiresIn: '24h' }
    );

    res.status(201).json({
      success: true,
      data: {
        token,
        user: {
          id: newUser.id,
          username: newUser.username,
          email: newUser.email
        }
      },
      message: 'Usuario registrado exitosamente'
    });
  } catch (error) {
    console.error('Error en registro:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor'
    });
  }
});

// POST - Login de usuario
app.post('/api/auth/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    
    console.log('🔐 Intento de login:', { username, passwordLength: password?.length });

    if (!username || !password) {
      console.log('❌ Faltan credenciales');
      return res.status(400).json({
        success: false,
        message: 'Usuario y contraseña son requeridos'
      });
    }

    // Buscar usuario
    const user = users.find(u => u.username === username || u.email === username);
    console.log('👤 Usuario encontrado:', user ? 'Sí' : 'No');
    
    if (!user) {
      console.log('❌ Usuario no existe');
      return res.status(401).json({
        success: false,
        message: 'Credenciales inválidas'
      });
    }

    console.log('🔍 Verificando contraseña...');
    // Verificar contraseña
    const validPassword = await bcrypt.compare(password, user.password);
    console.log('🔑 Contraseña válida:', validPassword);
    
    if (!validPassword) {
      console.log('❌ Contraseña incorrecta');
      return res.status(401).json({
        success: false,
        message: 'Credenciales inválidas'
      });
    }

    // Crear token
    const token = jwt.sign(
      { 
        userId: user.id, 
        username: user.username,
        email: user.email
      },
      JWT_SECRET,
      { expiresIn: '24h' }
    );

    console.log('✅ Login exitoso para:', username);

    res.json({
      success: true,
      data: {
        token,
        user: {
          id: user.id,
          username: user.username,
          email: user.email
        }
      },
      message: 'Login exitoso'
    });
  } catch (error) {
    console.error('💥 Error en login:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor'
    });
  }
});

// GET - Verificar token y obtener usuario actual
app.get('/api/auth/me', authenticateToken, (req, res) => {
  const user = users.find(u => u.id === req.user.userId);
  if (!user) {
    return res.status(404).json({
      success: false,
      message: 'Usuario no encontrado'
    });
  }

  res.json({
    success: true,
    data: {
      user: {
        id: user.id,
        username: user.username,
        email: user.email
      }
    },
    message: 'Usuario autenticado'
  });
});

// GET - Debug: Listar usuarios (solo para desarrollo)
app.get('/api/debug/users', (req, res) => {
  res.json({
    success: true,
    data: users.map(u => ({
      id: u.id,
      username: u.username,
      email: u.email,
      hasPassword: !!u.password
    })),
    message: 'Lista de usuarios para debug'
  });
});

// Rutas de la API (ahora protegidas)

// GET - Obtener todas las tareas del usuario autenticado
app.get('/api/tasks', authenticateToken, (req, res) => {
  console.log('GET /api/tasks - Obteniendo tareas del usuario:', req.user.username);
  
  // Filtrar tareas por usuario
  const userTasks = tasks.filter(task => task.userId === req.user.userId);
  
  res.json({
    success: true,
    data: userTasks,
    message: 'Tareas obtenidas exitosamente'
  });
});

// GET - Obtener una tarea por ID (solo del usuario autenticado)
app.get('/api/tasks/:id', authenticateToken, (req, res) => {
  const taskId = parseInt(req.params.id);
  const task = tasks.find(t => t.id === taskId && t.userId === req.user.userId);
  
  if (!task) {
    return res.status(404).json({
      success: false,
      message: 'Tarea no encontrada'
    });
  }
  
  console.log(`GET /api/tasks/${taskId} - Tarea encontrada`);
  res.json({
    success: true,
    data: task,
    message: 'Tarea obtenida exitosamente'
  });
});

// POST - Crear nueva tarea (asociada al usuario autenticado)
app.post('/api/tasks', authenticateToken, (req, res) => {
  const { title, description } = req.body;
  
  if (!title || !description) {
    return res.status(400).json({
      success: false,
      message: 'Título y descripción son requeridos'
    });
  }
  
  const newTask = {
    id: nextId++,
    title,
    description,
    completed: false,
    createdAt: new Date().toISOString(),
    userId: req.user.userId
  };
  
  tasks.push(newTask);
  console.log('POST /api/tasks - Nueva tarea creada por:', req.user.username, '- Tarea:', newTask.title);
  
  res.status(201).json({
    success: true,
    data: newTask,
    message: 'Tarea creada exitosamente'
  });
});

// PUT - Actualizar tarea (solo del usuario autenticado)
app.put('/api/tasks/:id', authenticateToken, (req, res) => {
  const taskId = parseInt(req.params.id);
  const { title, description, completed } = req.body;
  
  const taskIndex = tasks.findIndex(t => t.id === taskId && t.userId === req.user.userId);
  
  if (taskIndex === -1) {
    return res.status(404).json({
      success: false,
      message: 'Tarea no encontrada'
    });
  }
  
  // Actualizar campos
  if (title !== undefined) tasks[taskIndex].title = title;
  if (description !== undefined) tasks[taskIndex].description = description;
  if (completed !== undefined) tasks[taskIndex].completed = completed;
  
  console.log(`PUT /api/tasks/${taskId} - Tarea actualizada por:`, req.user.username);
  
  res.json({
    success: true,
    data: tasks[taskIndex],
    message: 'Tarea actualizada exitosamente'
  });
});

// DELETE - Eliminar tarea (solo del usuario autenticado)
app.delete('/api/tasks/:id', authenticateToken, (req, res) => {
  const taskId = parseInt(req.params.id);
  const taskIndex = tasks.findIndex(t => t.id === taskId && t.userId === req.user.userId);
  
  if (taskIndex === -1) {
    return res.status(404).json({
      success: false,
      message: 'Tarea no encontrada'
    });
  }
  
  const deletedTask = tasks.splice(taskIndex, 1)[0];
  console.log(`DELETE /api/tasks/${taskId} - Tarea eliminada por:`, req.user.username, '- Tarea:', deletedTask.title);
  
  res.json({
    success: true,
    data: deletedTask,
    message: 'Tarea eliminada exitosamente'
  });
});

// Ruta de salud del servidor
app.get('/api/health', (req, res) => {
  res.json({
    success: true,
    message: 'Backend funcionando correctamente',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Middleware para rutas no encontradas
app.use('*', (req, res) => {
  res.status(404).json({
    success: false,
    message: 'Ruta no encontrada'
  });
});

// Middleware para manejo de errores
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({
    success: false,
    message: 'Error interno del servidor'
  });
});

// Iniciar servidor
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Backend corriendo en puerto ${PORT}`);
  console.log(`📡 API disponible en http://localhost:${PORT}/api`);
  console.log('🔍 Rutas disponibles:');
  console.log('  POST   /api/auth/register');
  console.log('  POST   /api/auth/login');
  console.log('  GET    /api/auth/me');
  console.log('  GET    /api/debug/users (desarrollo)');
  console.log('  GET    /api/health');
  console.log('  GET    /api/tasks (protegida)');
  console.log('  GET    /api/tasks/:id (protegida)');
  console.log('  POST   /api/tasks (protegida)');
  console.log('  PUT    /api/tasks/:id (protegida)');
  console.log('  DELETE /api/tasks/:id (protegida)');
  console.log('');
  console.log('👥 Usuarios de prueba:');
  console.log('  - admin / admin123');
  console.log('  - usuario / admin123');
  console.log('');
  console.log('🧪 Para debug:');
  console.log(`  curl http://localhost:${PORT}/api/debug/users`);
});