const { transporter } = require('../config/email');

/**
 * Send a 6-digit password reset OTP to the user's email.
 * @param {string} toEmail - recipient email address
 * @param {string} otp - 6-digit OTP code
 */
async function sendOtpEmail(toEmail, otp) {
  const mailOptions = {
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to: toEmail,
    subject: 'Password Reset Code — Finance Tracker',
    text:
      `Your password reset code is: ${otp}\n\n` +
      `This code expires in 1 hour.\n\n` +
      `If you did not request a password reset, please ignore this email.`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 420px; margin: 0 auto; padding: 24px;">
        <h2 style="color: #1a73e8; margin-bottom: 4px;">Finance Tracker</h2>
        <h3 style="margin-top: 0;">Password Reset Code</h3>
        <p>You requested a password reset. Use the following code to set a new password:</p>
        <div style="font-size: 32px; font-weight: bold; letter-spacing: 8px; text-align: center;
                    padding: 20px; background: #f0f4ff; border-radius: 8px; margin: 20px 0;
                    color: #1a73e8;">${otp}</div>
        <p style="color: #666; font-size: 14px; margin-top: 24px;">
          This code expires in 1 hour.
        </p>
        <p style="color: #666; font-size: 14px;">
          If you did not request a password reset, you can safely ignore this email.
        </p>
      </div>
    `,
  };

  await transporter.sendMail(mailOptions);
}

module.exports = { sendOtpEmail };
