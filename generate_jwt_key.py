#!/usr/bin/env python3
"""
Script để generate JWT secret key ngẫu nhiên và thêm vào file .env
"""

import os
import secrets
import sys

def generate_jwt_secret(length=32):
    """Generate a secure random JWT secret key"""
    return secrets.token_hex(length)

def update_env_file(env_file_path, secret_key):
    """Update or add JWT_SECRET to .env file"""
    env_content = ""

    # Đọc file .env hiện tại nếu tồn tại
    if os.path.exists(env_file_path):
        with open(env_file_path, 'r', encoding='utf-8') as f:
            env_content = f.read()

    # Tách thành lines
    lines = env_content.split('\n') if env_content else []

    # Kiểm tra xem JWT_SECRET đã tồn tại chưa
    jwt_secret_found = False
    for i, line in enumerate(lines):
        if line.startswith('JWT_SECRET='):
            lines[i] = f'JWT_SECRET={secret_key}'
            jwt_secret_found = True
            break

    # Nếu chưa có, thêm vào cuối
    if not jwt_secret_found:
        if lines and lines[-1].strip():  # Nếu file không rỗng và dòng cuối không rỗng
            lines.append('')
        lines.append(f'JWT_SECRET={secret_key}')

    # Ghi lại file
    with open(env_file_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    print(f"Đã cập nhật JWT_SECRET trong {env_file_path}")

def main():
    # Path tới file .env (từ thư mục hiện tại)
    env_file_backend = 'invoice_app_backend/.env'

    # Generate secret key
    secret_key = generate_jwt_secret()
    print(f"🔑 Generated JWT Secret Key: {secret_key}")

    # Update backend .env file
    update_env_file(env_file_backend, secret_key)

    print("🎉 Hoàn thành! JWT_SECRET đã được thêm/cập nhật trong .env")

if __name__ == "__main__":
    main()