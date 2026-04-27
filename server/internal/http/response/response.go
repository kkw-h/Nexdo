package response

import "github.com/gin-gonic/gin"

func OK(c *gin.Context, data any, status ...int) {
	code := 200
	if len(status) > 0 {
		code = status[0]
	}
	c.JSON(code, gin.H{
		"code":    0,
		"message": "ok",
		"data":    data,
	})
}

func Fail(c *gin.Context, status, code int, message, detail string) {
	body := gin.H{
		"code":    code,
		"message": message,
	}
	if detail != "" {
		body["error"] = detail
	}
	c.JSON(status, body)
}
