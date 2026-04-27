package app

import (
	"nexdo-server-golang/internal/models"

	"github.com/gin-gonic/gin"
)

func publicUser(user models.User) gin.H {
	return gin.H{
		"id":         user.ID,
		"email":      user.Email,
		"nickname":   user.Nickname,
		"avatar_url": user.AvatarURL,
		"timezone":   user.Timezone,
		"locale":     user.Locale,
		"created_at": user.CreatedAt,
		"updated_at": user.UpdatedAt,
	}
}
