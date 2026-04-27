package app

import (
	"net/http"

	"nexdo-server-golang/internal/http/response"

	"github.com/gin-gonic/gin"
)

func (a *Application) handleListReminders(c *gin.Context) error {
	items, err := newReminderService(a).list(c.MustGet("userID").(string), ginContextAdapter{ctx: c})
	if err != nil {
		return err
	}
	response.OK(c, items)
	return nil
}

func (a *Application) handleGetReminder(c *gin.Context) error {
	view, err := newReminderService(a).get(c.MustGet("userID").(string), c.Param("id"))
	if err != nil {
		return err
	}
	response.OK(c, view)
	return nil
}

func (a *Application) handleReminderLogs(c *gin.Context) error {
	logs, err := newReminderService(a).logs(c.MustGet("userID").(string), c.Param("id"))
	if err != nil {
		return err
	}
	response.OK(c, logs)
	return nil
}

func (a *Application) handleCreateReminder(c *gin.Context) error {
	var req reminderPayload
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	item, err := newReminderService(a).create(c.MustGet("userID").(string), req)
	if err != nil {
		return err
	}
	response.OK(c, item, http.StatusCreated)
	return nil
}

func (a *Application) handlePatchReminder(c *gin.Context) error {
	var req updateReminderPayload
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	item, err := newReminderService(a).patch(c.MustGet("userID").(string), c.Param("id"), req)
	if err != nil {
		return err
	}
	response.OK(c, item)
	return nil
}

func (a *Application) handleDeleteReminder(c *gin.Context) error {
	if err := newReminderService(a).delete(c.MustGet("userID").(string), c.Param("id")); err != nil {
		return err
	}
	response.OK(c, gin.H{"deleted": true})
	return nil
}

func (a *Application) handleCompleteReminder(c *gin.Context) error {
	item, err := newReminderService(a).complete(c.MustGet("userID").(string), c.Param("id"))
	if err != nil {
		return err
	}
	response.OK(c, item)
	return nil
}

func (a *Application) handleUncompleteReminder(c *gin.Context) error {
	view, err := newReminderService(a).uncomplete(c.MustGet("userID").(string), c.Param("id"))
	if err != nil {
		return err
	}
	response.OK(c, view)
	return nil
}
