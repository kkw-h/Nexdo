package app

import (
	"strings"

	"nexdo-server-golang/internal/http/response"

	"github.com/gin-gonic/gin"
)

func (a *Application) handleListLists(c *gin.Context) error  { return a.listResources(c, "lists") }
func (a *Application) handleListGroups(c *gin.Context) error { return a.listResources(c, "groups") }
func (a *Application) handleListTags(c *gin.Context) error   { return a.listResources(c, "tags") }

func (a *Application) handleCreateList(c *gin.Context) error {
	var req listPayload
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if strings.TrimSpace(req.Name) == "" {
		return badRequest("name 必填")
	}
	model, err := newResourceService(a).createList(c.MustGet("userID").(string), req)
	if err != nil {
		return err
	}
	response.OK(c, model, 201)
	return nil
}

func (a *Application) handlePatchList(c *gin.Context) error {
	var req updateListPayload
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if req.Name != nil && strings.TrimSpace(*req.Name) == "" {
		return badRequest("name 必填")
	}
	item, err := newResourceService(a).patchList(c.MustGet("userID").(string), c.Param("id"), req)
	if err != nil {
		return err
	}
	response.OK(c, item)
	return nil
}

func (a *Application) handleDeleteList(c *gin.Context) error {
	if err := newResourceService(a).deleteList(c.MustGet("userID").(string), c.Param("id")); err != nil {
		return err
	}
	response.OK(c, gin.H{"deleted": true})
	return nil
}

func (a *Application) handleCreateGroup(c *gin.Context) error {
	var req groupPayload
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if strings.TrimSpace(req.Name) == "" {
		return badRequest("name 必填")
	}
	model, err := newResourceService(a).createGroup(c.MustGet("userID").(string), req)
	if err != nil {
		return err
	}
	response.OK(c, model, 201)
	return nil
}

func (a *Application) handlePatchGroup(c *gin.Context) error {
	var req updateGroupPayload
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if req.Name != nil && strings.TrimSpace(*req.Name) == "" {
		return badRequest("name 必填")
	}
	item, err := newResourceService(a).patchGroup(c.MustGet("userID").(string), c.Param("id"), req)
	if err != nil {
		return err
	}
	response.OK(c, item)
	return nil
}

func (a *Application) handleDeleteGroup(c *gin.Context) error {
	if err := newResourceService(a).deleteGroup(c.MustGet("userID").(string), c.Param("id")); err != nil {
		return err
	}
	response.OK(c, gin.H{"deleted": true})
	return nil
}

func (a *Application) handleCreateTag(c *gin.Context) error {
	var req tagPayload
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if strings.TrimSpace(req.Name) == "" {
		return badRequest("name 必填")
	}
	model, err := newResourceService(a).createTag(c.MustGet("userID").(string), req)
	if err != nil {
		return err
	}
	response.OK(c, model, 201)
	return nil
}

func (a *Application) handlePatchTag(c *gin.Context) error {
	var req updateTagPayload
	if err := decodeJSON(c, &req); err != nil {
		return err
	}
	if req.Name != nil && strings.TrimSpace(*req.Name) == "" {
		return badRequest("name 必填")
	}
	item, err := newResourceService(a).patchTag(c.MustGet("userID").(string), c.Param("id"), req)
	if err != nil {
		return err
	}
	response.OK(c, item)
	return nil
}

func (a *Application) handleDeleteTag(c *gin.Context) error {
	if err := newResourceService(a).deleteTag(c.MustGet("userID").(string), c.Param("id")); err != nil {
		return err
	}
	response.OK(c, gin.H{"deleted": true})
	return nil
}

func (a *Application) listResources(c *gin.Context, table string) error {
	service := newResourceService(a)
	userID := c.MustGet("userID").(string)
	switch table {
	case "lists":
		items, err := service.listLists(userID)
		if err != nil {
			return err
		}
		response.OK(c, items)
	case "groups":
		items, err := service.listGroups(userID)
		if err != nil {
			return err
		}
		response.OK(c, items)
	case "tags":
		items, err := service.listTags(userID)
		if err != nil {
			return err
		}
		response.OK(c, items)
	}
	return nil
}
