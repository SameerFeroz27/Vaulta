const { z } = require('zod');

const registerSchema = z.object({
  email: z
    .string({ required_error: 'Email is required' })
    .email('Invalid email address')
    .trim()
    .toLowerCase(),
  password: z
    .string({ required_error: 'Password is required' })
    .min(8, 'Password must be at least 8 characters long')
    .max(100, 'Password cannot exceed 100 characters'),
  name: z
    .string({ required_error: 'Name is required' })
    .trim()
    .min(2, 'Name must be at least 2 characters long')
    .max(50, 'Name cannot exceed 50 characters'),
  currency: z
    .string()
    .length(3, 'Currency must be 3-letter ISO code')
    .toUpperCase()
    .default('PKR')
    .optional(),
  timezone: z
    .string()
    .default('Asia/Karachi')
    .optional(),
});

const loginSchema = z.object({
  email: z
    .string({ required_error: 'Email is required' })
    .email('Invalid email address')
    .trim()
    .toLowerCase(),
  password: z
    .string({ required_error: 'Password is required' }),
});

const refreshSchema = z.object({
  refreshToken: z
    .string({ required_error: 'Refresh token is required' }),
});

const forgotPasswordSchema = z.object({
  email: z
    .string({ required_error: 'Email is required' })
    .email('Invalid email address')
    .trim()
    .toLowerCase(),
});

const resetPasswordSchema = z.object({
  token: z
    .string({ required_error: 'OTP code is required' })
    .length(6, 'OTP must be exactly 6 digits')
    .regex(/^\d{6}$/, 'OTP must contain only digits'),
  password: z
    .string({ required_error: 'Password is required' })
    .min(8, 'Password must be at least 8 characters long')
    .max(100, 'Password cannot exceed 100 characters'),
});

const changePasswordSchema = z.object({
  currentPassword: z
    .string({ required_error: 'Current password is required' }),
  newPassword: z
    .string({ required_error: 'New password is required' })
    .min(8, 'Password must be at least 8 characters long')
    .max(100, 'Password cannot exceed 100 characters'),
});

module.exports = {
  registerSchema,
  loginSchema,
  refreshSchema,
  forgotPasswordSchema,
  resetPasswordSchema,
  changePasswordSchema,
};
