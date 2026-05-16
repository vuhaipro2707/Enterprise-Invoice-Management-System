package app

import (
	"invoice_backend/app/auth"
	"invoice_backend/app/invoice"
	"invoice_backend/app/item"
	sqlc "invoice_backend/db/sqlc"

	"github.com/gofiber/fiber/v2"
)

func SetupRoutes(app *fiber.App, repo *sqlc.Queries) {
	// Khởi tạo các Handlers
	authHandler := auth.NewAuthHandler(repo)
	itemHandler := item.NewItemHandler(repo)
	invoiceHandler := invoice.NewInvoiceHandler(repo)

	authGroup := app.Group("/auth")
	authGroup.Post("/login", authHandler.Login)
	authGroup.Post("/register", authHandler.Register)
	authGroup.Get("/me", auth.JWTMiddleware(), authHandler.GetCurrentUser)
	authGroup.Post("/signingDevice", auth.JWTMiddleware(), invoiceHandler.RegisterDevice)
	authGroup.Get("/checkRegistered", auth.JWTMiddleware(), invoiceHandler.CheckRegistered)

	itemGroup := app.Group("/item", auth.JWTMiddleware())
	itemGroup.Post("", itemHandler.CreateItem)
	itemGroup.Get("", itemHandler.GetItems)
	itemGroup.Get("/search", itemHandler.SearchItems)
	itemGroup.Patch("/:itemId", itemHandler.PatchItem)
	itemGroup.Post("/otherName/itemId/:itemId", itemHandler.AddItemOtherName)
	itemGroup.Delete("/otherName/:otherNameId", itemHandler.RemoveItemOtherName)

	itemGroup.Post("/unit/itemId/:itemId", itemHandler.CreateUnitForItem)
	itemGroup.Get("/unit", itemHandler.GetUnits)
	itemGroup.Patch("/unit/:unitId", itemHandler.PatchUnit)
	itemGroup.Delete("/unit/:unitId", itemHandler.DeleteUnit)

	itemGroup.Post("/type", itemHandler.CreateType)
	itemGroup.Get("/types", itemHandler.GetTypes)
	itemGroup.Patch("/type/:typeId", itemHandler.PatchType)

	invoiceGroup := app.Group("/invoice", auth.JWTMiddleware())
	invoiceGroup.Post("", invoiceHandler.CreateInvoice)
	invoiceGroup.Patch("/:invoiceId", invoiceHandler.PatchInvoice)
	invoiceGroup.Post("/lineItem/invoiceId/:invoiceId", invoiceHandler.CreateLineItem)
	invoiceGroup.Patch("/lineItem/:lineItemId", invoiceHandler.PatchLineItem)
	invoiceGroup.Get("/buyer", invoiceHandler.GetBuyers)
	invoiceGroup.Get("/buyer/next-code", invoiceHandler.GetNextBuyerCode)
	invoiceGroup.Get("/buyer/search", invoiceHandler.SearchBuyers)
	invoiceGroup.Get("/google/autocomplete", invoiceHandler.GooglePlaceAutocomplete)
	invoiceGroup.Get("/google/details", invoiceHandler.GooglePlaceDetails)
	invoiceGroup.Post("/buyer", invoiceHandler.CreateBuyer)
	invoiceGroup.Patch("/buyer/:buyerId", invoiceHandler.PatchBuyer)
	invoiceGroup.Post("/takeTurn/invoiceId/:invoiceId", invoiceHandler.TakeTurn)
	invoiceGroup.Post("/finish/invoiceId/:invoiceId", invoiceHandler.Finish)
	invoiceGroup.Get("/ping/invoiceId/:invoiceId", invoiceHandler.PingInvoice)
}
