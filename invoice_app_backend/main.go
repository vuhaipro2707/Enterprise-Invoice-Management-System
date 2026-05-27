package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/gofiber/fiber/v2"
	"github.com/joho/godotenv"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	_ "github.com/lib/pq"
	"golang.org/x/crypto/bcrypt"

	router "invoice_backend/app"
	"invoice_backend/app/backup"
	"invoice_backend/app/dbconn"
	"invoice_backend/app/print"

	sqlc "invoice_backend/db/sqlc"

	"github.com/robfig/cron/v3"
)

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func main() {
	// 1. Load Environment Variables on Startup
	err := godotenv.Load(".env")
	if err != nil {
		dir, _ := os.Getwd()
		fmt.Printf("Error: .env file not found at: %s/%s\n", dir, ".env")
	} else {
		fmt.Println("Successfully loaded .env file")
	}

	// 2. Read Environment Variables
	dbHost := "localhost"
	if os.Getenv("APP_ENV") == "production" {
		dbHost = getEnv("POSTGRES_HOST", "localhost")
	}
	dbPort := getEnv("POSTGRES_PORT", "5432")
	dbUser := getEnv("POSTGRES_USER", "admin")
	dbPass := getEnv("POSTGRES_PASSWORD", "123")
	dbName := getEnv("POSTGRES_DB", "invoice_management")
	appPort := getEnv("PORT", "8080")

	// 3. Setup DB Connection
	fmt.Println("Connecting to Database at:", dbHost)
	fmt.Println("App is preparing to run on Port:", appPort)

	dbURL := fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=disable", dbUser, dbPass, dbHost, dbPort, dbName)

	runDBMigration("file://db/migrations", dbURL)

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatal(err)
	}

	// Setup DB connection sharing for starting transactions in services
	dbconn.DB = db

	repo := sqlc.New(db)

	ctx := context.Background()

	// 3. Initialize Admin Account if not exists (Idempotent)
	_, err = repo.GetAccountByUsername(ctx, "admin")
	if err != nil {
		if err == sql.ErrNoRows {
			adminPassword := getEnv("ADMIN_PASSWORD", "admin")
			hashedPassword, hashErr := bcrypt.GenerateFromPassword([]byte(adminPassword), bcrypt.DefaultCost)
			if hashErr != nil {
				log.Fatal("Error hashing password for Admin:", hashErr)
			}

			_, err = repo.CreateAccount(ctx, sqlc.CreateAccountParams{
				Username: "admin",
				Name:     "System Admin",
				Password: string(hashedPassword),
			})
			if err != nil {
				log.Println("⚠️ Error initializing Admin account:", err)
			} else {
				fmt.Println("✅ Admin account initialized successfully!")
			}
		} else {
			log.Println("⚠️ Error checking Admin account:", err)
		}
	} else {
		fmt.Println("ℹ️ Admin account already exists, skipping initialization.")
	}

	// 3.5 Initialize Global Settings if not exists (Idempotent)
	defaultMail := getEnv("DEFAULT_MAIL", "FromHaideptraiWithLove@gmail.com")
	companyName := getEnv("COMPANY_NAME", "Công ty Hải Minh")
	phoneNumber := getEnv("PHONE_NUMBER", "0909090909")

	settingsMap := map[string]interface{}{
		"default_mail": defaultMail,
		"company_name": companyName,
		"phone_number": phoneNumber,
	}
	settingsBytes, err := json.Marshal(settingsMap)
	if err == nil {
		_, initErr := repo.InsertGlobalSettings(ctx, json.RawMessage(settingsBytes))
		switch initErr {
		case nil:
			fmt.Println("✅ Global Settings initialized successfully.")
		case sql.ErrNoRows:
			fmt.Println("✅ Global Settings already exist, skipping initialization.")
		default:
			fmt.Println("⚠️ Error initializing Global Settings:", initErr)
		}
	}

	app := fiber.New()

	// 4. Setup CORS Middleware (Only for local development. In production, Nginx handles CORS)
	if os.Getenv("APP_ENV") != "production" {
		app.Use(func(c *fiber.Ctx) error {
			c.Set("Access-Control-Allow-Origin", "*")
			c.Set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,PATCH,OPTIONS")
			c.Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Device-Holding-ID")
			c.Set("Access-Control-Expose-Headers", "X-Polled-Jobs-Count")

			if c.Method() == "OPTIONS" {
				return c.SendStatus(204)
			}
			return c.Next()
		})
	}

	app.Get("/ping", func(c *fiber.Ctx) error {
		return c.Status(200).JSON(fiber.Map{
			"message": "Go Backend is ready!",
			"db_info": fiber.Map{
				"host": dbHost,
				"port": dbPort,
				"user": dbUser,
				"name": dbName,
			},
		})
	})

	// 4. Setup Routes after Repo is initialized
	router.SetupRoutes(app, repo)

	// --- CONFIGURE BACKUP CRONJOB ---
	backupService := backup.NewBackupService(repo)
	c := cron.New()
	_, cronErr := c.AddFunc("*/10 * * * *", func() {
		_ = backupService.RunBackupTask(context.Background())
	})
	if cronErr != nil {
		log.Printf("❌ Cron configuration error: %v\n", cronErr)
	} else {
		c.Start()
		fmt.Println("⏰ Automatic database backup CronJob activated (every 10 minutes)")
	}

	// --- START BACKGROUND PRINT QUEUE MONITOR DAEMON ---
	printService := print.NewPrintService(repo)
	printDaemon := print.NewPrintDaemon(printService, "./printing_folder")
	printDaemon.SyncAndStart(context.Background())

	// 5. Start Application on specified Port
	log.Fatal(app.Listen(":" + appPort))
}

func runDBMigration(migrationURL string, dbURL string) {
	m, err := migrate.New(migrationURL, dbURL)
	if err != nil {
		log.Fatal("Could not initialize migrations:", err)
	}

	// Up command automatically compares versions and runs missing migrations
	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		log.Fatal("Error running migrations up:", err)
	}

	log.Println("Database migration completed (or no change detected)!")
}
