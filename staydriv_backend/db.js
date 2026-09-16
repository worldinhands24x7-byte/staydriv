/**
 * StayDriv - Unified Database Connector
 * Supports both MySQL and MongoDB (hybrid/switchable)
 */
require('dotenv').config();

const dbType = (process.env.DB_TYPE || 'mongodb').toLowerCase();

let mysqlPool = null;

if (dbType === 'mysql' || process.env.MYSQL_HOST) {
  try {
    const mysql = require('mysql2/promise');
    mysqlPool = mysql.createPool({
      host: process.env.MYSQL_HOST || '127.0.0.1',
      port: parseInt(process.env.MYSQL_PORT || '3306', 10),
      user: process.env.MYSQL_USER || 'staydriv_user',
      password: process.env.MYSQL_PASSWORD || '',
      database: process.env.MYSQL_DATABASE || 'staydriv_db',
      waitForConnections: true,
      connectionLimit: 10,
      queueLimit: 0,
      enableKeepAlive: true,
      keepAliveInitialDelay: 0
    });

    console.log(`[DATABASE] MySQL Pool initialized for host: ${process.env.MYSQL_HOST || '127.0.0.1'}, db: ${process.env.MYSQL_DATABASE || 'staydriv_db'}`);
  } catch (err) {
    console.error('[DATABASE] Error initializing MySQL pool:', err.message);
  }
}

async function queryMySQL(sql, params = []) {
  if (!mysqlPool) {
    throw new Error('MySQL pool is not configured. Check your MYSQL_* environment variables in .env');
  }
  const [results] = await mysqlPool.execute(sql, params);
  return results;
}

module.exports = {
  dbType,
  mysqlPool,
  queryMySQL
};
