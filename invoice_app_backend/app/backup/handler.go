package backup

import (
	sqlc "invoice_backend/db/sqlc"

	"github.com/gofiber/fiber/v2"
)

type BackupHandler struct {
	Repo    *sqlc.Queries
	service *BackupService
}

func NewBackupHandler(repo *sqlc.Queries) *BackupHandler {
	return &BackupHandler{
		Repo:    repo,
		service: NewBackupService(repo),
	}
}

// TriggerBackup triggers the backup and Drive upload synchronously to provide instant validation feedback
func (h *BackupHandler) TriggerBackup(c *fiber.Ctx) error {
	err := h.service.RunBackupTask(c.UserContext())
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Backup process failed: " + err.Error(),
		})
	}

	return c.Status(200).JSON(fiber.Map{
		"message": "Manual backup process completed successfully and uploaded to Google Drive.",
	})
}
