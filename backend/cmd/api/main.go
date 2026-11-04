package main

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	router := gin.Default()

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"message": "Nekadaja API is running",
		})
	})

	log.Println("Nekadaja API running on :8080")

	if err := router.Run(":8082"); err != nil {
		log.Fatal(err)
	}
}
