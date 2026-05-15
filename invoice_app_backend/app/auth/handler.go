package auth

import (
	"context"
	sqlc "invoice_backend/db/sqlc" // Đổi theo module của bạn

	"github.com/gofiber/fiber/v2"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct {
	Repo *sqlc.Queries
}

// Hàm khởi tạo để main.go gọi vào
func NewAuthHandler(repo *sqlc.Queries) *AuthHandler {
	return &AuthHandler{Repo: repo}
}

func (h *AuthHandler) Login(c *fiber.Ctx) error {
	type LoginRequest struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}

	var req LoginRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: username, password"})
	}

	if req.Username == "" || req.Password == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: username, password"})
	}

	// Kiểm tra DB qua Repo
	user, err := h.Repo.GetAccountByUsername(context.Background(), req.Username)
	if err != nil {
		return c.Status(401).JSON(fiber.Map{"error": "Invalid username or password"})
	}

	// So sánh password đã hash
	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password)); err != nil {
		return c.Status(401).JSON(fiber.Map{"error": "Invalid username or password"})
	}

	// Gen JWT
	token, _ := GenerateToken(user.Username)

	return c.JSON(fiber.Map{
		"message": "Login successful!",
		"token":   token,
	})
}

func (h *AuthHandler) Register(c *fiber.Ctx) error {
	type RegisterRequest struct {
		Username string `json:"username"`
		Name     string `json:"name"`
		Password string `json:"password"`
	}

	var req RegisterRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: username, name, password"})
	}

	if req.Username == "" || req.Name == "" || req.Password == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: username, name, password"})
	}

	// Kiểm tra username đã tồn tại chưa
	_, err := h.Repo.GetAccountByUsername(context.Background(), req.Username)
	if err == nil {
		return c.Status(409).JSON(fiber.Map{"error": "Username already exists"})
	}

	// Hash password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Server error"})
	}

	// Tạo account mới
	_, err = h.Repo.CreateAccount(context.Background(), sqlc.CreateAccountParams{
		Username: req.Username,
		Name:     req.Name,
		Password: string(hashedPassword),
	})
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Error creating account"})
	}

	return c.Status(201).JSON(fiber.Map{"message": "Registration successful!"})
}

func (h *AuthHandler) GetCurrentUser(c *fiber.Ctx) error {
	username := c.Locals("username").(string)

	user, err := h.Repo.GetAccountByUsername(context.Background(), username)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "User not found"})
	}

	return c.JSON(fiber.Map{
		"account_id": user.AccountID,
		"username":   user.Username,
		"name":       user.Name,
		"is_active":  user.IsActive,
		"created_at": user.CreatedAt,
		"updated_at": user.UpdatedAt,
	})
}

