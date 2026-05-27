package app

import (
	"invoice_backend/app/auth"
	"invoice_backend/app/globalsettings"
	"invoice_backend/app/invoice"
	"invoice_backend/app/item"
	"invoice_backend/app/pricelist"
	"invoice_backend/app/print"
	"invoice_backend/app/release"
	"invoice_backend/app/backup"
	sqlc "invoice_backend/db/sqlc"

	"github.com/gofiber/fiber/v2"
)

func SetupRoutes(app *fiber.App, repo *sqlc.Queries) {
	// Khởi tạo các Handlers
	authHandler := auth.NewAuthHandler(repo)
	itemHandler := item.NewItemHandler(repo)
	invoiceHandler := invoice.NewInvoiceHandler(repo)
	pricelistHandler := pricelist.NewPriceListHandler(repo)
	printHandler := print.NewPrintHandler(repo)
	globalsettingsHandler := globalsettings.NewGlobalSettingsHandler(repo)
	releaseHandler := release.NewReleaseHandler(repo)
	backupHandler := backup.NewBackupHandler(repo)

	releaseGroup := app.Group("/release")
	releaseGroup.Get("/version", releaseHandler.GetVersion)
	releaseGroup.Get("/download", releaseHandler.DownloadApk)

	authGroup := app.Group("/auth")
	authGroup.Post("/login", authHandler.Login)
	authGroup.Post("/register", authHandler.Register)
	authGroup.Get("/me", auth.JWTMiddleware(), authHandler.GetCurrentUser)
	authGroup.Post("/signingDevice", auth.JWTMiddleware(), invoiceHandler.RegisterDevice)
	authGroup.Get("/checkRegistered", auth.JWTMiddleware(), invoiceHandler.CheckRegistered)

	itemGroup := app.Group("/item", auth.JWTMiddleware())
	itemGroup.Post("", itemHandler.CreateItem)
	itemGroup.Get("", itemHandler.GetItems)
	itemGroup.Get("/deleted", itemHandler.GetDeletedItems)
	itemGroup.Get("/search", itemHandler.SearchItems)
	itemGroup.Patch("/id/:itemId", itemHandler.PatchItem)
	itemGroup.Delete("/id/:itemId", itemHandler.DeleteItem)
	itemGroup.Post("/id/:itemId/restore", itemHandler.RestoreItem)
	itemGroup.Post("/otherName/itemId/:itemId", itemHandler.AddItemOtherName)
	itemGroup.Delete("/otherName/id/:otherNameId", itemHandler.RemoveItemOtherName)
	itemGroup.Post("/ai-generate", itemHandler.AIGenerateItemSuggestions)
	itemGroup.Post("/ai-batch-create", itemHandler.AIBatchCreateItems)

	itemGroup.Post("/unit/itemId/:itemId", itemHandler.CreateUnitForItem)
	itemGroup.Get("/unit", itemHandler.GetUnits)
	itemGroup.Patch("/unit/id/:unitId", itemHandler.PatchUnit)
	itemGroup.Delete("/unit/id/:unitId", itemHandler.DeleteUnit)

	itemGroup.Post("/type", itemHandler.CreateType)
	itemGroup.Get("/types", itemHandler.GetTypes)
	itemGroup.Patch("/type/id/:typeId", itemHandler.PatchType)
	itemGroup.Delete("/type/id/:typeId", itemHandler.DeleteType)

	invoiceGroup := app.Group("/invoice", auth.JWTMiddleware())
	invoiceGroup.Get("", invoiceHandler.GetInvoices)
	invoiceGroup.Get("/deleted", invoiceHandler.GetDeletedInvoices)
	invoiceGroup.Get("/next-code", invoiceHandler.GetNextInvoiceCode)
	invoiceGroup.Get("/buyer", invoiceHandler.GetBuyers)
	invoiceGroup.Get("/buyer/deleted", invoiceHandler.GetDeletedBuyers)
	invoiceGroup.Get("/buyer/next-code", invoiceHandler.GetNextBuyerCode)
	invoiceGroup.Get("/buyer/by-code", invoiceHandler.GetBuyerByCode)
	invoiceGroup.Get("/buyer/search", invoiceHandler.SearchBuyers)
	invoiceGroup.Get("/google/autocomplete", invoiceHandler.GooglePlaceAutocomplete)
	invoiceGroup.Get("/google/details", invoiceHandler.GooglePlaceDetails)
	invoiceGroup.Get("/google/reverse-geocode", invoiceHandler.GoogleReverseGeocode)
	invoiceGroup.Get("/google/geocode", invoiceHandler.GoogleGeocode)
	invoiceGroup.Post("", invoiceHandler.CreateInvoice)
	invoiceGroup.Delete("/id/:invoiceId", invoiceHandler.DeleteInvoice)
	invoiceGroup.Post("/id/:invoiceId/restore", invoiceHandler.RestoreInvoice)
	invoiceGroup.Post("/buyer", invoiceHandler.CreateBuyer)
	invoiceGroup.Patch("/buyer/id/:buyerId", invoiceHandler.PatchBuyer)
	invoiceGroup.Delete("/buyer/id/:buyerId", invoiceHandler.DeleteBuyer)
	invoiceGroup.Post("/buyer/id/:buyerId/restore", invoiceHandler.RestoreBuyer)
	invoiceGroup.Post("/takeTurn/invoiceId/:invoiceId", invoiceHandler.TakeTurn)
	invoiceGroup.Get("/ping/invoiceId/:invoiceId", invoiceHandler.PingInvoice)
	invoiceGroup.Get("/id/:invoiceId", invoiceHandler.GetInvoiceWithLines)
	invoiceGroup.Get("/id/:invoiceId/export", invoiceHandler.ExportInvoice)
	invoiceGroup.Post("/lock/invoiceId/:invoiceId", invoiceHandler.LockInvoice)
	invoiceGroup.Post("/clone", invoiceHandler.CloneInvoice)

	// Các route yêu cầu phải đang giữ quyền chỉnh sửa (Edit Lock)
	invoiceLockGroup := invoiceGroup.Group("", auth.CheckHoldingDevice(repo))
	invoiceLockGroup.Patch("/id/:invoiceId", invoiceHandler.PatchInvoice)
	invoiceLockGroup.Post("/lineItem/invoiceId/:invoiceId", invoiceHandler.CreateLineItem)
	invoiceLockGroup.Patch("/lineItem/changeOrder/:invoiceId", invoiceHandler.ChangeLineItemOrder)
	invoiceLockGroup.Patch("/lineItem/id/:lineItemId", invoiceHandler.PatchLineItem)
	invoiceLockGroup.Delete("/lineItem/id/:lineItemId", invoiceHandler.DeleteLineItem)
	invoiceLockGroup.Post("/finish/invoiceId/:invoiceId", invoiceHandler.Finish)

	pricelistGroup := app.Group("/pricelist", auth.JWTMiddleware())
	pricelistGroup.Post("", pricelistHandler.CreatePriceList)
	pricelistGroup.Get("", pricelistHandler.GetPriceLists)
	pricelistGroup.Get("/deleted", pricelistHandler.GetDeletedPriceLists)
	pricelistGroup.Get("/id/:pricelistId", pricelistHandler.GetPriceListByID)
	pricelistGroup.Patch("/id/:pricelistId", pricelistHandler.UpdatePriceList)
	pricelistGroup.Patch("/changeOrder/:pricelistId", pricelistHandler.ChangePriceItemOrder)
	pricelistGroup.Delete("/id/:pricelistId", pricelistHandler.DeletePriceList)
	pricelistGroup.Post("/id/:pricelistId/restore", pricelistHandler.RestorePriceList)
	pricelistGroup.Get("/id/:pricelistId/export", pricelistHandler.ExportPriceList)
	pricelistGroup.Post("/id/:pricelistId/export-email", pricelistHandler.ExportAndEmailPriceList)

	printGroup := app.Group("/print", auth.JWTMiddleware())
	printGroup.Post("", printHandler.CreatePrintJob)
	printGroup.Get("", printHandler.GetPrintJobs)
	printGroup.Get("/poll", printHandler.PollPrintJob)
	printGroup.Post("/poll-all", printHandler.PollAllQueue)
	printGroup.Patch("/id/:printJobId", printHandler.UpdatePrintJobStatus)

	settingsGroup := app.Group("/settings", auth.JWTMiddleware())
	settingsGroup.Get("", globalsettingsHandler.GetSettings)
	settingsGroup.Patch("", globalsettingsHandler.UpdateSettings)

	// Public Trigger Backup Route
	app.Get("/api/trigger-backup", backupHandler.TriggerBackup)
}
