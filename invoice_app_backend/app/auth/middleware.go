package auth

import (
	"context"
	sqlc "invoice_backend/db/sqlc"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
)

func CheckHoldingDevice(repo *sqlc.Queries) fiber.Handler {
	return func(c *fiber.Ctx) error {
		invoiceIDStr := c.Params("invoiceId")
		lineItemIDStr := c.Params("lineItemId")

		if invoiceIDStr == "" && lineItemIDStr == "" {
			path := c.Path()
			parts := strings.Split(path, "/")
			for i, part := range parts {
				if part == "id" && i+1 < len(parts) {
					if _, err := uuid.Parse(parts[i+1]); err == nil {
						invoiceIDStr = parts[i+1]
						break
					}
				}
				if part == "lineItem" && i+2 < len(parts) && parts[i+1] == "id" {
					if _, err := uuid.Parse(parts[i+2]); err == nil {
						lineItemIDStr = parts[i+2]
						break
					}
				}
				if part == "invoiceId" && i+1 < len(parts) {
					if _, err := uuid.Parse(parts[i+1]); err == nil {
						invoiceIDStr = parts[i+1]
						break
					}
				}
			}
		}

		var invoiceID uuid.UUID
		var err error

		if invoiceIDStr != "" {
			invoiceID, err = uuid.Parse(invoiceIDStr)
			if err != nil {
				return c.Status(400).JSON(fiber.Map{"error": "Invalid invoiceId format"})
			}
		} else if lineItemIDStr != "" {
			lineItemID, err := uuid.Parse(lineItemIDStr)
			if err != nil {
				return c.Status(400).JSON(fiber.Map{"error": "Invalid lineItemId format"})
			}
			lineItem, err := repo.GetLineItemByID(context.Background(), lineItemID)
			if err != nil {
				return c.Status(404).JSON(fiber.Map{"error": "Line item not found"})
			}
			if !lineItem.InvoiceID.Valid {
				return c.Status(400).JSON(fiber.Map{"error": "Line item has no associated invoice"})
			}
			invoiceID = lineItem.InvoiceID.UUID
		} else {
			return c.Next()
		}

		currentDeviceID := c.Get("X-Device-Holding-ID")
		if currentDeviceID == "" {
			return c.Status(400).JSON(fiber.Map{"error": "Missing header: X-Device-Holding-ID"})
		}

		invoice, err := repo.GetInvoiceByID(context.Background(), invoiceID)
		if err != nil {
			return c.Status(404).JSON(fiber.Map{"error": "Invoice not found"})
		}

		if !invoice.EditStatus.Bool || !invoice.DeviceHoldingID.Valid || invoice.DeviceHoldingID.String != currentDeviceID {
			return c.Status(403).JSON(fiber.Map{
				"error":           "Permission denied: Invoice is not in edit mode or you do not hold the lock",
				"deviceHoldingId": invoice.DeviceHoldingID.String,
				"editStatus":      invoice.EditStatus.Bool,
			})
		}

		return c.Next()
	}
}
