package jwtutil

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int64  `json:"expires_in"`
}

type Claims struct {
	TokenKind string `json:"token_kind"`
	SessionID string `json:"session_id"`
	jwt.RegisteredClaims
}

type IssueResult struct {
	Pair             TokenPair
	RefreshTokenID   string
	RefreshExpiresAt time.Time
}

func IssuePair(userID, sessionID string, accessSecret, refreshSecret string, accessTTL, refreshTTL time.Duration) (IssueResult, error) {
	now := time.Now().UTC()
	accessToken, err := issue(userID, sessionID, "", "access", accessSecret, now, accessTTL)
	if err != nil {
		return IssueResult{}, err
	}
	refreshTokenID := uuid.NewString()
	refreshExpiresAt := now.Add(refreshTTL)
	refreshToken, err := issue(userID, sessionID, refreshTokenID, "refresh", refreshSecret, now, refreshTTL)
	if err != nil {
		return IssueResult{}, err
	}
	return IssueResult{
		Pair: TokenPair{
			AccessToken:  accessToken,
			RefreshToken: refreshToken,
			TokenType:    "Bearer",
			ExpiresIn:    int64(accessTTL.Seconds()),
		},
		RefreshTokenID:   refreshTokenID,
		RefreshExpiresAt: refreshExpiresAt,
	}, nil
}

func issue(userID, sessionID, tokenID, kind, secret string, now time.Time, ttl time.Duration) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, Claims{
		TokenKind: kind,
		SessionID: sessionID,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			ID:        tokenID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
		},
	})
	return token.SignedString([]byte(secret))
}

func Parse(tokenString, secret, expectedKind string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid || claims.TokenKind != expectedKind {
		return nil, jwt.ErrTokenInvalidClaims
	}
	return claims, nil
}
