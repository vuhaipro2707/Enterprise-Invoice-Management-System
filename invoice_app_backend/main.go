package main

import (
	"fmt"
	"log"
	"os"

	"github.com/gofiber/fiber/v2"
	"github.com/joho/godotenv"
)

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func main() {
	// 1. Load Env ngay lập tức khi vào App
	err := godotenv.Load(".env") // Chỉ định rõ tên file
	if err != nil {
		// Lấy đường dẫn thư mục hiện tại để xem Go đang đứng ở đâu
		dir, _ := os.Getwd()
		fmt.Printf("❌ Lỗi: Không tìm thấy file .env tại: %s/%s\n", dir, ".env")
	} else {
		fmt.Println("✅ Đã load thành công file .env")
	}

	// 2. Đọc biến (Nên dùng os.Getenv trực tiếp cho gọn nếu đã có hàm fallback)
	dbHost := getEnv("DB_HOST", "localhost")
	dbPort := getEnv("DB_PORT", "5432")
	dbUser := getEnv("DB_USER", "admin")
	dbPass := getEnv("DB_PASSWORD", "123")
	dbName := getEnv("DB_NAME", "invoice_management")
	appPort := getEnv("PORT", "8080")

	// 3. In ra để kiểm tra TRƯỚC khi Listen
	fmt.Println("🚀 Đang kết nối tới DB tại:", dbHost)
	fmt.Println("📡 App chuẩn bị chạy ở Port:", appPort)

	app := fiber.New()

	app.Get("/api/v1/ping", func(c *fiber.Ctx) error {
		return c.Status(200).JSON(fiber.Map{
			"message": "Backend Go đã sẵn sàng!",
			"db_info": fiber.Map{
				"host": dbHost,
				"port": dbPort,
				"user": dbUser,
				"pass": dbPass,
				"name": dbName,
			},
		})
	})

	// 4. Dòng này phải nằm cuối cùng của hàm main
	log.Fatal(app.Listen(":" + appPort))
}
