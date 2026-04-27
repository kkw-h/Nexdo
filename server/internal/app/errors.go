package app

type AppError struct {
	Status  int
	Code    int
	Message string
	Detail  string
}

func (e *AppError) Error() string {
	return e.Message
}

func badRequest(message string) *AppError {
	return &AppError{Status: 400, Code: 40000, Message: "请求参数错误", Detail: message}
}

func badRequestWithCode(code int, message string) *AppError {
	return &AppError{Status: 400, Code: code, Message: "请求参数错误", Detail: message}
}

func unauthorized(message string) *AppError {
	if message == "" {
		message = "未授权"
	}
	return &AppError{Status: 401, Code: 40100, Message: message, Detail: message}
}

func unauthorizedWithCode(code int, message string) *AppError {
	return &AppError{Status: 401, Code: code, Message: message, Detail: message}
}

func conflict(code int, message string) *AppError {
	return &AppError{Status: 409, Code: code, Message: message, Detail: message}
}

func notFound(message string) *AppError {
	if message == "" {
		message = "资源不存在"
	}
	return &AppError{Status: 404, Code: 40400, Message: message, Detail: message}
}

func internal(detail string) *AppError {
	return &AppError{Status: 500, Code: 50000, Message: "服务器内部错误", Detail: detail}
}
