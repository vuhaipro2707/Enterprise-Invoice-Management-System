- Dev Phase

Generate JWT for Backend:

```
python generate_jwt_key.py
```

Run Go Backend (Hot Reload):

```
air init
air
```

Generate SQLC Code:
```
sqlc generate
```

Run Flutter Frontend Engine:

running emulator device

running by debug (.vscode/launch.json)



Build Image (Before Deploy):
docker buildx build --platform linux/amd64 -t haideptrai2707/invoice_backend:v1 . --push


- Deploy Phase

Script Auto Deploy

```
chmod +x setup.sh
sudo ./setup.sh
```