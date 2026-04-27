package app

import (
	"strings"

	"nexdo-server-golang/internal/models"

	"github.com/gin-gonic/gin"
)

func (a *Application) recordDeviceFromRequest(c *gin.Context, userID string) (string, error) {
	deviceID := strings.TrimSpace(c.GetHeader(deviceIDHeader))
	if deviceID == "" {
		return "", nil
	}
	userAgent := c.GetHeader("User-Agent")
	ipAddress := strings.TrimSpace(c.ClientIP())
	deviceName := strings.TrimSpace(c.GetHeader(deviceNameHeader))
	platform := strings.TrimSpace(c.GetHeader(devicePlatformHeader))
	if deviceName == "" || platform == "" {
		uaPlatform, uaName := parseUserAgentDetails(userAgent)
		if deviceName == "" {
			deviceName = uaName
		}
		if platform == "" {
			platform = uaPlatform
		}
	}
	if deviceName == "" {
		deviceName = "未知设备"
	}
	now := nowISO()
	var existing models.Device
	err := a.db.Where("device_id = ?", deviceID).First(&existing).Error
	if err == nil {
		existing.UserID = userID
		if deviceName != "" {
			existing.DeviceName = deviceName
		}
		if platform != "" {
			existing.Platform = platform
		}
		if userAgent != "" {
			existing.UserAgent = userAgent
		}
		if ipAddress != "" {
			existing.IPAddress = ipAddress
		}
		existing.LastSeenAt = now
		existing.UpdatedAt = now
		return deviceID, a.db.Save(&existing).Error
	}
	device := models.Device{
		ID:         newID(),
		UserID:     userID,
		DeviceID:   deviceID,
		DeviceName: deviceName,
		Platform:   platform,
		UserAgent:  userAgent,
		IPAddress:  ipAddress,
		LastSeenAt: now,
		CreatedAt:  now,
		UpdatedAt:  now,
	}
	return deviceID, a.db.Create(&device).Error
}

func parseUserAgentDetails(userAgent string) (string, string) {
	start := strings.Index(userAgent, "(")
	end := strings.Index(userAgent, ")")
	if start < 0 || end <= start {
		return "", ""
	}
	parts := strings.Split(userAgent[start+1:end], ";")
	if len(parts) == 0 {
		return "", ""
	}
	platform := strings.TrimSpace(parts[0])
	deviceName := ""
	if len(parts) > 1 {
		deviceName = strings.TrimSpace(parts[1])
	}
	return platform, deviceName
}
