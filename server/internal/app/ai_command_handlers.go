package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"nexdo-server-golang/internal/http/response"

	"github.com/gin-gonic/gin"
)

func (a *Application) handleResolveAICommand(c *gin.Context) error {
	startedAt := time.Now()
	var req aiCommandResolveRequest
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if strings.TrimSpace(req.Input) == "" {
		return badRequest("input 必填")
	}
	a.logAIEvent(
		"resolve_start",
		c,
		fmt.Sprintf("input_length=%d", len(strings.TrimSpace(req.Input))),
	)
	result, err := newAICommandService(a).resolve(c.MustGet("userID").(string), req.Input)
	if err != nil {
		a.logAIError("resolve_failed", c, err)
		return err
	}
	a.logAIEvent(
		"resolve_done",
		c,
		fmt.Sprintf(
			"elapsed_ms=%d mode=%s status=%s requires_confirmation=%t",
			time.Since(startedAt).Milliseconds(),
			result.Mode,
			result.Result.Status,
			result.Result.RequiresConfirmation,
		),
	)
	response.OK(c, result)
	return nil
}

func (a *Application) handleResolveAICommandStream(c *gin.Context) {
	startedAt := time.Now()
	var req aiCommandResolveRequest
	if err := decodeJSON(c, &req); err != nil {
		a.writeAICommandStreamError(c, err)
		return
	}
	if strings.TrimSpace(req.Input) == "" {
		a.writeAICommandStreamError(c, badRequest("input 必填"))
		return
	}
	a.logAIEvent(
		"resolve_stream_start",
		c,
		fmt.Sprintf("input_length=%d", len(strings.TrimSpace(req.Input))),
	)

	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")
	c.Writer.Header().Set("X-Accel-Buffering", "no")
	c.Status(http.StatusOK)

	flusher, ok := c.Writer.(http.Flusher)
	if !ok {
		a.writeAICommandStreamError(c, internal("stream flush not supported"))
		return
	}

	writeEvent := func(event string, payload any) error {
		body, err := json.Marshal(payload)
		if err != nil {
			return err
		}
		if _, err := c.Writer.WriteString("event: " + event + "\n"); err != nil {
			return err
		}
		if _, err := c.Writer.WriteString("data: " + string(body) + "\n\n"); err != nil {
			return err
		}
		flusher.Flush()
		a.logAIEvent(
			"resolve_stream_event",
			c,
			fmt.Sprintf("event=%s payload=%s", event, string(body)),
		)
		return nil
	}

	if err := writeEvent("status", aiCommandStreamStatusPayload{
		Stage:   "accepted",
		Message: "已接收指令，开始处理",
	}); err != nil {
		return
	}

	result, err := newAICommandService(a).resolveWithProgress(
		c.MustGet("userID").(string),
		req.Input,
		func(event aiCommandStreamStatusPayload) {
			_ = writeEvent("status", event)
		},
	)
	if err != nil {
		a.logAIError("resolve_stream_failed", c, err)
		a.writeAICommandStreamError(c, err)
		return
	}
	if err := writeEvent("result", result); err != nil {
		return
	}
	_ = writeEvent("done", aiCommandStreamStatusPayload{
		Stage:   "done",
		Message: "处理完成",
	})
	a.logAIEvent(
		"resolve_stream_done",
		c,
		fmt.Sprintf(
			"elapsed_ms=%d mode=%s status=%s requires_confirmation=%t",
			time.Since(startedAt).Milliseconds(),
			result.Mode,
			result.Result.Status,
			result.Result.RequiresConfirmation,
		),
	)
}

func (a *Application) writeAICommandStreamError(c *gin.Context, err error) {
	var appErr *AppError
	payload := aiCommandStreamErrorPayload{
		Code:    50000,
		Message: "服务器内部错误",
		Detail:  err.Error(),
	}
	if errors.As(err, &appErr) {
		payload.Code = appErr.Code
		payload.Message = appErr.Message
		payload.Detail = appErr.Detail
	}
	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")
	c.Writer.Header().Set("X-Accel-Buffering", "no")
	c.Status(http.StatusOK)
	if body, marshalErr := json.Marshal(payload); marshalErr == nil {
		_, _ = c.Writer.WriteString("event: error\n")
		_, _ = c.Writer.WriteString("data: " + string(body) + "\n\n")
		if flusher, ok := c.Writer.(http.Flusher); ok {
			flusher.Flush()
		}
	}
}

func (a *Application) handleVerifyAIConfirmation(c *gin.Context) error {
	startedAt := time.Now()
	var req aiCommandVerifyRequest
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if strings.TrimSpace(req.Token) == "" {
		return badRequest("token 必填")
	}
	a.logAIEvent(
		"verify_start",
		c,
		fmt.Sprintf("token_length=%d", len(strings.TrimSpace(req.Token))),
	)
	result, err := newAICommandService(a).verifyConfirmationToken(req.Token)
	if err != nil {
		a.logAIError("verify_failed", c, err)
		return err
	}
	a.logAIEvent(
		"verify_done",
		c,
		fmt.Sprintf(
			"elapsed_ms=%d valid=%t action=%s",
			time.Since(startedAt).Milliseconds(),
			result.Valid,
			result.Claims.Action,
		),
	)
	response.OK(c, result)
	return nil
}

func (a *Application) handleExecuteAIConfirmation(c *gin.Context) error {
	startedAt := time.Now()
	var req aiCommandExecuteRequest
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if strings.TrimSpace(req.Token) == "" {
		return badRequest("token 必填")
	}
	a.logAIEvent(
		"execute_start",
		c,
		fmt.Sprintf("token_length=%d", len(strings.TrimSpace(req.Token))),
	)
	result, err := newAICommandService(a).executeConfirmationToken(c.MustGet("userID").(string), req.Token)
	if err != nil {
		if appErr, ok := err.(*AppError); ok {
			a.logAIEvent(
				"execute_failed_detail",
				c,
				fmt.Sprintf("code=%d message=%s detail=%s", appErr.Code, appErr.Message, appErr.Detail),
			)
		}
		a.logAIError("execute_failed", c, err)
		return err
	}
	a.logAIEvent(
		"execute_done",
		c,
		fmt.Sprintf(
			"elapsed_ms=%d executed=%t action=%s result_count=%d",
			time.Since(startedAt).Milliseconds(),
			result.Executed,
			result.Action,
			len(result.Result),
		),
	)
	response.OK(c, result)
	return nil
}
