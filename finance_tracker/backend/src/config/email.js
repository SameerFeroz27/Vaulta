const nodemailer = require('nodemailer');

/**
 * Gmail SMTP transporter for sending transactional emails (password reset OTP).
 * Credentials come from .env — see SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS.
 */
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: parseInt(process.env.SMTP_PORT || '587', 10),
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

module.exports = { transporter };
