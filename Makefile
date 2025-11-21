# Makefile for Simple API (Spring Boot)
# Author: Generated for Softbank Backend Project

# Variables
GRADLE = ./gradlew
DOCKER_IMAGE_NAME = ghcr.io/johnhuh619/softbank_be
DOCKER_COMPOSE = docker-compose
BUILD_DIR = build
GRADLE_CACHE = .gradle

# Colors for output
GREEN = \033[0;32m
YELLOW = \033[0;33m
RED = \033[0;31m
NC = \033[0m # No Color

.PHONY: all test build clean fclean re docker-build docker-run docker-stop docker-restart help

# Default target - Build and run in Docker
all: docker-build docker-run
	@echo "$(GREEN)✅ Application is running in Docker!$(NC)"
	@echo "$(YELLOW)📊 Access the app at: http://localhost:8080$(NC)"
	@echo "$(YELLOW)📊 Health check: http://localhost:8080/actuator/health$(NC)"

# Run tests
test:
	@echo "$(YELLOW)🧪 Running tests...$(NC)"
	@chmod +x $(GRADLE)
	@$(GRADLE) test --no-daemon
	@echo "$(GREEN)✅ All tests passed!$(NC)"

# Build JAR file
build:
	@echo "$(YELLOW)📦 Building JAR...$(NC)"
	@chmod +x $(GRADLE)
	@$(GRADLE) clean bootJar --no-daemon
	@echo "$(GREEN)✅ JAR built successfully!$(NC)"

# Clean build directory
clean:
	@echo "$(YELLOW)🧹 Cleaning build directory...$(NC)"
	@chmod +x $(GRADLE)
	@$(GRADLE) clean --no-daemon
	@echo "$(GREEN)✅ Clean completed!$(NC)"

# Full clean (including Gradle cache and Docker images)
fclean: clean
	@echo "$(YELLOW)🗑️  Performing full clean...$(NC)"
	@rm -rf $(BUILD_DIR)
	@rm -rf $(GRADLE_CACHE)
	@rm -rf logs/*.log
	@echo "$(YELLOW)🐳 Stopping and removing Docker containers...$(NC)"
	@$(DOCKER_COMPOSE) down -v 2>/dev/null || true
	@docker rmi $(DOCKER_IMAGE_NAME):latest 2>/dev/null || true
	@echo "$(GREEN)✅ Full clean completed!$(NC)"

# Rebuild everything (clean + build + run in Docker)
re: fclean all
	@echo "$(GREEN)✅ Rebuild and deployment completed!$(NC)"

# Restart Docker containers (quick restart without rebuild)
docker-restart:
	@echo "$(YELLOW)🔄 Restarting Docker container...$(NC)"
	@$(DOCKER_COMPOSE) restart
	@echo "$(GREEN)✅ Container restarted!$(NC)"

# Build Docker image
docker-build: build
	@echo "$(YELLOW)🐳 Building Docker image...$(NC)"
	@docker build -t $(DOCKER_IMAGE_NAME):latest .
	@echo "$(GREEN)✅ Docker image built!$(NC)"

# Run Docker container
docker-run:
	@echo "$(YELLOW)🚀 Starting Docker container...$(NC)"
	@$(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✅ Container started!$(NC)"
	@echo "$(YELLOW)📊 Container status:$(NC)"
	@$(DOCKER_COMPOSE) ps

# Stop Docker container
docker-stop:
	@echo "$(YELLOW)🛑 Stopping Docker container...$(NC)"
	@$(DOCKER_COMPOSE) down
	@echo "$(GREEN)✅ Container stopped!$(NC)"

# View logs
logs:
	@echo "$(YELLOW)📜 Viewing logs...$(NC)"
	@$(DOCKER_COMPOSE) logs -f

# Run application locally (without Docker)
run:
	@echo "$(YELLOW)🚀 Running application locally...$(NC)"
	@chmod +x $(GRADLE)
	@$(GRADLE) bootRun

# Check code style (if you add checkstyle later)
check:
	@echo "$(YELLOW)🔍 Checking code style...$(NC)"
	@chmod +x $(GRADLE)
	@$(GRADLE) check --no-daemon

# Show help
help:
	@echo "$(GREEN)Simple API - Available Commands:$(NC)"
	@echo ""
	@echo "$(GREEN)🐳 Docker Commands (Default):$(NC)"
	@echo "  $(YELLOW)make all$(NC)              - Build and run in Docker (default)"
	@echo "  $(YELLOW)make re$(NC)               - Full rebuild and run in Docker (fclean + all)"
	@echo "  $(YELLOW)make docker-build$(NC)     - Build Docker image"
	@echo "  $(YELLOW)make docker-run$(NC)       - Start Docker container"
	@echo "  $(YELLOW)make docker-stop$(NC)      - Stop Docker container"
	@echo "  $(YELLOW)make docker-restart$(NC)   - Restart Docker container (quick)"
	@echo "  $(YELLOW)make logs$(NC)             - View container logs"
	@echo ""
	@echo "$(GREEN)🛠️  Build & Test:$(NC)"
	@echo "  $(YELLOW)make test$(NC)             - Run all tests"
	@echo "  $(YELLOW)make build$(NC)            - Build JAR file only"
	@echo "  $(YELLOW)make check$(NC)            - Check code style"
	@echo ""
	@echo "$(GREEN)🧹 Clean:$(NC)"
	@echo "  $(YELLOW)make clean$(NC)            - Clean build directory"
	@echo "  $(YELLOW)make fclean$(NC)           - Full clean (build + cache + Docker)"
	@echo ""
	@echo "$(GREEN)💻 Local Development:$(NC)"
	@echo "  $(YELLOW)make run$(NC)              - Run application locally (without Docker)"
	@echo ""
	@echo "  $(YELLOW)make help$(NC)             - Show this help message"
	@echo ""
