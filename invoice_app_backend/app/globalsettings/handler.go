package globalsettings

import (
	"encoding/json"
	"fmt"
	sqlc "invoice_backend/db/sqlc"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type GlobalSettingsHandler struct {
	Repo    *sqlc.Queries
	service *GlobalSettingsService
}

func NewGlobalSettingsHandler(repo *sqlc.Queries) *GlobalSettingsHandler {
	return &GlobalSettingsHandler{
		Repo:    repo,
		service: NewGlobalSettingsService(repo),
	}
}

func (h *GlobalSettingsHandler) GetSettings(c *fiber.Ctx) error {
	ctx := c.Context()
	settings, err := h.service.GetSettings(ctx)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{
			"error": "Global settings not found. Please restart server to seed.",
		})
	}
	return c.Status(200).JSON(settings)
}

func (h *GlobalSettingsHandler) UpdateSettings(c *fiber.Ctx) error {
	ctx := c.Context()
	
	// Read raw body to parse dynamic map for precise key validation
	var rawMap map[string]interface{}
	if err := c.BodyParser(&rawMap); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid JSON body. Required keys: default_mail, company_name, phone_number",
		})
	}

	var missingKeys []string
	valMail, hasMail := rawMap["default_mail"]
	if !hasMail || valMail == nil || strings.TrimSpace(fmt.Sprint(valMail)) == "" {
		missingKeys = append(missingKeys, "default_mail")
	}
	valCompany, hasCompany := rawMap["company_name"]
	if !hasCompany || valCompany == nil || strings.TrimSpace(fmt.Sprint(valCompany)) == "" {
		missingKeys = append(missingKeys, "company_name")
	}
	valPhone, hasPhone := rawMap["phone_number"]
	if !hasPhone || valPhone == nil || strings.TrimSpace(fmt.Sprint(valPhone)) == "" {
		missingKeys = append(missingKeys, "phone_number")
	}

	if len(missingKeys) > 0 {
		return c.Status(400).JSON(fiber.Map{
			"error": "Missing required keys: " + strings.Join(missingKeys, ", "),
		})
	}

	// Re-marshal map to RawMessage
	configBytes, err := json.Marshal(rawMap)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Internal server error marshalling config",
		})
	}

	updated, err := h.service.UpdateSettings(ctx, configBytes)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to update global settings: " + err.Error(),
		})
	}

	return c.Status(200).JSON(updated)
}
