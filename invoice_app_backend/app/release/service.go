package release

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

type ReleaseService struct{}

func NewReleaseService() *ReleaseService {
	return &ReleaseService{}
}

// GetVersion reads and parses the version string from pubspec.yaml
func (s *ReleaseService) GetVersion() (string, error) {
	// If running in production container, use the exact production volume mount path
	if os.Getenv("APP_ENV") == "production" {
		prodPath := "/invoice_app_frontend/pubspec.yaml"
		return s.parseVersion(prodPath)
	}

	// Search in multiple logical locations (dev, docker, custom paths)
	paths := []string{
		"../invoice_app_frontend/pubspec.yaml",
		"./pubspec.yaml",
		"/app/pubspec.yaml",
		"./invoice_app_frontend/pubspec.yaml",
	}

	var lastErr error
	for _, path := range paths {
		if _, err := os.Stat(path); err == nil {
			version, err := s.parseVersion(path)
			if err == nil {
				return version, nil
			}
			lastErr = err
		} else {
			lastErr = err
		}
	}

	if lastErr != nil {
		return "", fmt.Errorf("failed to read pubspec.yaml: %w", lastErr)
	}
	return "", fmt.Errorf("pubspec.yaml not found in search paths")
}

func (s *ReleaseService) parseVersion(filePath string) (string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return "", err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "version:") {
			versionPart := strings.TrimSpace(strings.TrimPrefix(line, "version:"))
			// Remove comments if any
			parts := strings.Split(versionPart, "#")
			return strings.TrimSpace(parts[0]), nil
		}
	}
	return "", fmt.Errorf("version key not found in pubspec.yaml")
}

// GetApkPath resolves the release APK file path
func (s *ReleaseService) GetApkPath() (string, error) {
	// If running in production container, use the exact production volume mount path
	if os.Getenv("APP_ENV") == "production" {
		prodPath := "/invoice_app_frontend/build/app/outputs/apk/release/app-release.apk"
		if _, err := os.Stat(prodPath); err == nil {
			return prodPath, nil
		}
		return "", fmt.Errorf("apk file not found in production path: %s", prodPath)
	}

	// Search in multiple logical locations (dev, docker, custom paths)
	paths := []string{
		"../invoice_app_frontend/build/app/outputs/apk/release/app-release.apk",
		"../invoice_app_frontend/build/app/outputs/flutter-apk/app-release.apk",
		"../flutter_apk/app-release.apk",
		"./app-release.apk",
		"/app/app-release.apk",
		"./flutter_apk/app-release.apk",
	}

	for _, path := range paths {
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}

	return "", fmt.Errorf("apk file not found in search paths")
}
