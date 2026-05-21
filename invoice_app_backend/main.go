package main

import (
	"context"
	"database/sql"
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
	"invoice_backend/app/dbconn"

	sqlc "invoice_backend/db/sqlc"
)

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func main() {
	// 1. Load Env ngay lập tức khi vào App
	err := godotenv.Load(".env")
	if err != nil {
		dir, _ := os.Getwd()
		fmt.Printf("Lỗi: Không tìm thấy file .env tại: %s/%s\n", dir, ".env")
	} else {
		fmt.Println("Đã load thành công file .env")
	}

	// 2. Đọc biến (Nên dùng os.Getenv trực tiếp cho gọn nếu đã có hàm fallback)
	dbHost := getEnv("DB_HOST", "localhost")
	dbPort := getEnv("DB_PORT", "5432")
	dbUser := getEnv("DB_USER", "admin")
	dbPass := getEnv("DB_PASSWORD", "123")
	dbName := getEnv("DB_NAME", "invoice_management")
	appPort := getEnv("PORT", "8080")

	// 3. Setup DB Connection (Để sau khi đã có thông tin từ Env)
	fmt.Println("Đang kết nối tới DB tại:", dbHost)
	fmt.Println("App chuẩn bị chạy ở Port:", appPort)

	dbURL := fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=disable", dbUser, dbPass, dbHost, dbPort, dbName)

	runDBMigration("file://db/migrations", dbURL)

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatal(err)
	}

	// Thiết lập db cho connection sharing để có thể bắt đầu transactions trong services
	dbconn.DB = db

	repo := sqlc.New(db)

	ctx := context.Background()

	// Hash password cho admin
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte("admin"), bcrypt.DefaultCost)
	if err != nil {
		log.Fatal("Lỗi hash password:", err)
	}

	admin, err := repo.CreateAccount(ctx, sqlc.CreateAccountParams{
		Username: "admin",
		Name:     "Admin Hệ Thống",
		Password: string(hashedPassword),
	})

	admin, err = repo.GetAccountByUsername(ctx, "admin")

	if err == nil {
		fmt.Println("ℹ️ Admin đã tồn tại, bỏ qua bước khởi tạo.")
	} else {
		fmt.Printf("✅ Admin đã được tạo: %+v\n", admin)
	}

	app := fiber.New()

	// 4. Setup CORS Middleware
	app.Use(func(c *fiber.Ctx) error {
		c.Set("Access-Control-Allow-Origin", "*")
		c.Set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,PATCH,OPTIONS")
		c.Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Device-Holding-ID")
		
		if c.Method() == "OPTIONS" {
			return c.SendStatus(204)
		}
		return c.Next()
	})

	app.Get("/ping", func(c *fiber.Ctx) error {
		return c.Status(200).JSON(fiber.Map{
			"message": "Backend Go đã sẵn sàng!",
			"db_info": fiber.Map{
				"host": dbHost,
				"port": dbPort,
				"user": dbUser,
				"name": dbName,
			},
		})
	})

	// 4. Setup Routes sau khi đã có Repo
	router.SetupRoutes(app, repo)

	// 5. Chạy App với Port đã lấy từ Env
	log.Fatal(app.Listen(":" + appPort))
}

func runDBMigration(migrationURL string, dbURL string) {
	m, err := migrate.New(migrationURL, dbURL)
	if err != nil {
		log.Fatal("Không thể khởi tạo migration:", err)
	}

	// Lệnh Up này sẽ tự động so sánh version
	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		log.Fatal("Lỗi khi chạy migration up:", err)
	}

	log.Println("Database migration hoàn tất (hoặc không có thay đổi)!")
}
