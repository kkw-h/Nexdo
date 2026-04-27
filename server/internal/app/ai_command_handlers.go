package app

import (
	"strings"

	"nexdo-server-golang/internal/http/response"

	"github.com/gin-gonic/gin"
)

func (a *Application) handleResolveAICommand(c *gin.Context) error {
	var req aiCommandResolveRequest
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if strings.TrimSpace(req.Input) == "" {
		return badRequest("input 必填")
	}
	result, err := newAICommandService(a).resolve(c.MustGet("userID").(string), req.Input)
	if err != nil {
		return err
	}
	response.OK(c, result)
	return nil
}

func (a *Application) handleVerifyAIConfirmation(c *gin.Context) error {
	var req aiCommandVerifyRequest
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if strings.TrimSpace(req.Token) == "" {
		return badRequest("token 必填")
	}
	result, err := newAICommandService(a).verifyConfirmationToken(req.Token)
	if err != nil {
		return err
	}
	response.OK(c, result)
	return nil
}

func (a *Application) handleExecuteAIConfirmation(c *gin.Context) error {
	var req aiCommandExecuteRequest
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if strings.TrimSpace(req.Token) == "" {
		return badRequest("token 必填")
	}
	result, err := newAICommandService(a).executeConfirmationToken(c.MustGet("userID").(string), req.Token)
	if err != nil {
		return err
	}
	response.OK(c, result)
	return nil
}
