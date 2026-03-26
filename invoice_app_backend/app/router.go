package app

import (
	"invoice_backend/app/auth"
	sqlc "invoice_backend/db/sqlc"

	"github.com/gofiber/fiber/v2"
)

func SetupRoutes(app *fiber.App, repo *sqlc.Queries) {
	// Khởi tạo các Handlers
	authHandler := auth.NewAuthHandler(repo)
	// invoiceHandler := invoice.NewInvoiceHandler(repo) // Ví dụ sau này thêm

	authGroup := app.Group("/auth")
	authGroup.Post("/login", authHandler.Login)
	authGroup.Post("/register", authHandler.Register)
	authGroup.Get("/me", auth.JWTMiddleware(), authHandler.GetCurrentUser)

}
