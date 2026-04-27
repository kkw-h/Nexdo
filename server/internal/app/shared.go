package app

import "github.com/gin-gonic/gin"

type queryProvider interface {
	Query(key string) string
	QueryArray(key string) []string
}

type requestContextProvider interface {
	GinContext() *gin.Context
}

type ginContextAdapter struct {
	ctx *gin.Context
}

func (g ginContextAdapter) Query(key string) string {
	return g.ctx.Query(key)
}

func (g ginContextAdapter) QueryArray(key string) []string {
	return g.ctx.QueryArray(key)
}

func (g ginContextAdapter) GinContext() *gin.Context {
	return g.ctx
}
