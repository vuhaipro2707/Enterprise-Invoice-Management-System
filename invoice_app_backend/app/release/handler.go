package release

import (
	sqlc "invoice_backend/db/sqlc"
	"github.com/gofiber/fiber/v2"
)

type ReleaseHandler struct {
	Repo    *sqlc.Queries
	service *ReleaseService
}

func NewReleaseHandler(repo *sqlc.Queries) *ReleaseHandler {
	return &ReleaseHandler{
		Repo:    repo,
		service: NewReleaseService(),
	}
}

// GetVersion returns the version parsed from the frontend's pubspec.yaml
func (h *ReleaseHandler) GetVersion(c *fiber.Ctx) error {
	version, err := h.service.GetVersion()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to retrieve app version: " + err.Error(),
		})
	}
	return c.Status(200).JSON(fiber.Map{
		"version": version,
	})
}

// DownloadApk serves the app-release.apk file
func (h *ReleaseHandler) DownloadApk(c *fiber.Ctx) error {
	apkPath, err := h.service.GetApkPath()
	if err != nil {
		return c.Status(404).JSON(fiber.Map{
			"error": "APK file not found: " + err.Error(),
		})
	}

	// Set appropriate headers for APK download
	c.Set("Content-Type", "application/vnd.android.package-archive")
	c.Set("Content-Disposition", "attachment; filename=app-release.apk")

	return c.SendFile(apkPath)
}
