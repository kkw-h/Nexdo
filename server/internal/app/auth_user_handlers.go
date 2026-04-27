package app

import (
	"nexdo-server-golang/internal/http/response"

	"github.com/gin-gonic/gin"
)

func (a *Application) handleRegister(c *gin.Context) error {
	var req registerRequest
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	data, err := newAuthService(a).register(c, req)
	if err != nil {
		return err
	}
	response.OK(c, data, 201)
	return nil
}

func (a *Application) handleLogin(c *gin.Context) error {
	var req loginRequest
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	data, err := newAuthService(a).login(c, req)
	if err != nil {
		return err
	}
	response.OK(c, data)
	return nil
}

func (a *Application) handleRefresh(c *gin.Context) error {
	var req refreshRequest
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	data, err := newAuthService(a).refresh(c, req)
	if err != nil {
		return err
	}
	response.OK(c, data)
	return nil
}

func (a *Application) handleLogout(c *gin.Context) error {
	data, err := newAuthService(a).logout(c)
	if err != nil {
		return err
	}
	response.OK(c, data)
	return nil
}

func (a *Application) handleMe(c *gin.Context) error {
	data, err := newAuthService(a).currentUser(c)
	if err != nil {
		return err
	}
	response.OK(c, data)
	return nil
}

func (a *Application) handleUpdateMe(c *gin.Context) error {
	var req updateProfileRequest
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	data, err := newAuthService(a).updateProfile(c, req)
	if err != nil {
		return err
	}
	response.OK(c, data)
	return nil
}

func (a *Application) handlePassword(c *gin.Context) error {
	var req changePasswordRequest
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	data, err := newAuthService(a).changePassword(c, req)
	if err != nil {
		return err
	}
	response.OK(c, data)
	return nil
}

func (a *Application) handleDevices(c *gin.Context) error {
	data, err := newAuthService(a).devices(c)
	if err != nil {
		return err
	}
	response.OK(c, data)
	return nil
}

func (a *Application) handleDeleteDevice(c *gin.Context) error {
	data, err := newAuthService(a).deleteDevice(c, c.Param("id"))
	if err != nil {
		return err
	}
	response.OK(c, data)
	return nil
}
