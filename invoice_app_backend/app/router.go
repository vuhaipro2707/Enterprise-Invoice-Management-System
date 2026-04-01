package app

import (
	"invoice_backend/app/auth"
	"invoice_backend/app/item"
	sqlc "invoice_backend/db/sqlc"

	"github.com/gofiber/fiber/v2"
)

func SetupRoutes(app *fiber.App, repo *sqlc.Queries) {
	// Khởi tạo các Handlers
	authHandler := auth.NewAuthHandler(repo)
	itemHandler := item.NewItemHandler(repo)
	// invoiceHandler := invoice.NewInvoiceHandler(repo) // Ví dụ sau này thêm

	authGroup := app.Group("/auth")
	authGroup.Post("/login", authHandler.Login)
	authGroup.Post("/register", authHandler.Register)
	authGroup.Get("/me", auth.JWTMiddleware(), authHandler.GetCurrentUser)

	itemGroup := app.Group("/item", auth.JWTMiddleware())
	itemGroup.Post("", itemHandler.CreateItem)
	itemGroup.Get("", itemHandler.GetItems)
	itemGroup.Get("/search", itemHandler.SearchItems)

	itemGroup.Post("/unit/itemId/:itemId", itemHandler.CreateUnitForItem)
	itemGroup.Get("/unit", itemHandler.GetUnits)

	itemGroup.Post("/type", itemHandler.CreateType)
	itemGroup.Get("/type", itemHandler.GetTypes)

}
