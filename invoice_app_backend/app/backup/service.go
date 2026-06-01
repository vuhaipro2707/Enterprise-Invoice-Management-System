package backup

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"time"

	sqlc "invoice_backend/db/sqlc"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type BackupService struct {
	Repo *sqlc.Queries
}

func NewBackupService(repo *sqlc.Queries) *BackupService {
	return &BackupService{
		Repo: repo,
	}
}

// RunBackupTask executes the database pg_dump and uploads the SQL file to Cloudflare R2
func (s *BackupService) RunBackupTask(ctx context.Context) error {
	log.Println("⏱️ Starting automatic database backup process...")

	// 1. Get database settings and Cloudflare R2 configurations from environment
	dbHost := "localhost"
	if os.Getenv("APP_ENV") == "production" {
		dbHost = os.Getenv("POSTGRES_HOST")
		if dbHost == "" {
			dbHost = "localhost"
		}
	}
	dbPort := os.Getenv("POSTGRES_PORT")
	if dbPort == "" {
		dbPort = "5432"
	}
	dbUser := os.Getenv("POSTGRES_USER")
	if dbUser == "" {
		dbUser = "admin"
	}
	dbPass := os.Getenv("POSTGRES_PASSWORD")
	if dbPass == "" {
		dbPass = "123"
	}
	dbName := os.Getenv("POSTGRES_DB")
	if dbName == "" {
		dbName = "invoice_db"
	}

	accessKeyID := os.Getenv("R2_ACCESS_KEY_ID")
	secretAccessKey := os.Getenv("R2_SECRET_ACCESS_KEY")
	r2Endpoint := os.Getenv("R2_ENDPOINTS")
	bucketName := os.Getenv("R2_BUCKET_NAME")

	if accessKeyID == "" || secretAccessKey == "" || r2Endpoint == "" || bucketName == "" {
		log.Println("❌ Error: Missing Cloudflare R2 configurations in .env")
		return fmt.Errorf("missing Cloudflare R2 configurations in .env")
	}

	// 2. Ensure backups directory exists and define real-time file paths
	backupsDir := "./backups"
	if err := os.MkdirAll(backupsDir, 0755); err != nil {
		log.Printf("❌ Error creating backups directory: %v\n", err)
		return fmt.Errorf("failed to create backups directory: %w", err)
	}

	loc, err := time.LoadLocation("Asia/Ho_Chi_Minh")
	if err != nil {
		loc = time.Local
	}
	currentTime := time.Now().In(loc).Format("20060102-150405")
	fileName := fmt.Sprintf("backup-%s.sql", currentTime)
	filePath := fmt.Sprintf("%s/%s", backupsDir, fileName)

	// 3. Check if pg_dump is available on the host machine, otherwise use docker exec fallback
	_, errLookPath := exec.LookPath("pg_dump")
	if errLookPath == nil {
		log.Println("ℹ️ pg_dump found locally on host. Running host backup...")
		cmd := exec.Command("pg_dump", "-h", dbHost, "-p", dbPort, "-U", dbUser, "-d", dbName, "-f", filePath)
		cmd.Env = append(os.Environ(), fmt.Sprintf("PGPASSWORD=%s", dbPass))
		if err := cmd.Run(); err != nil {
			log.Printf("❌ Error running local pg_dump: %v\n", err)
			return fmt.Errorf("failed to run pg_dump locally: %w", err)
		}
	} else {
		log.Println("ℹ️ pg_dump not found in host PATH. Attempting fallback via Docker container (invoice_db_dev)...")

		// Create the local file to stream docker output into
		f, err := os.Create(filePath)
		if err != nil {
			log.Printf("❌ Error creating SQL backup file: %v\n", err)
			return fmt.Errorf("failed to create backup file: %w", err)
		}

		cmd := exec.Command("docker", "exec", "-e", fmt.Sprintf("PGPASSWORD=%s", dbPass), "invoice_db_dev", "pg_dump", "-U", dbUser, "-d", dbName)
		cmd.Stdout = f
		cmd.Stderr = os.Stderr // Pipe stderr to Go console to help debug if needed

		runErr := cmd.Run()
		f.Close() // Close file immediately to flush data and release file lock

		if runErr != nil {
			log.Printf("❌ Error running pg_dump inside Docker container: %v\n", runErr)
			_ = os.Remove(filePath)
			return fmt.Errorf("failed to run pg_dump inside docker: %w", runErr)
		}
	}
	log.Println("💾 SQL database successfully dumped locally.")

	// 4. Connect to Cloudflare R2 and Upload
	// Create custom endpoint resolver for Cloudflare R2 S3 compatibility
	r2Resolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
		return aws.Endpoint{
			URL:               r2Endpoint,
			HostnameImmutable: true,
			SigningRegion:     "auto",
		}, nil
	})

	// Load configuration with credentials
	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithEndpointResolverWithOptions(r2Resolver),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKeyID, secretAccessKey, "")),
		config.WithRegion("auto"),
	)
	if err != nil {
		log.Printf("❌ Error loading AWS R2 configuration: %v\n", err)
		return fmt.Errorf("failed to load R2 config: %w", err)
	}

	// Create S3 client
	s3Client := s3.NewFromConfig(cfg)

	// Open SQL file for streaming upload
	f, err := os.Open(filePath)
	if err != nil {
		log.Printf("❌ Error opening SQL file for upload: %v\n", err)
		return fmt.Errorf("failed to open backup file: %w", err)
	}
	defer f.Close()

	log.Printf("🚀 Uploading backup file %s to Cloudflare R2...\n", fileName)
	_, err = s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(bucketName),
		Key:    aws.String(fileName),
		Body:   f,
	})
	if err != nil {
		log.Printf("❌ Error uploading backup to Cloudflare R2: %v\n", err)
		return fmt.Errorf("failed to upload backup to R2: %w", err)
	}

	log.Printf("🚀 Success! Backup file %s successfully uploaded to Cloudflare R2!\n", fileName)

	log.Printf("💾 Backup file %s kept locally in %s.\n", fileName, backupsDir)
	return nil
}
