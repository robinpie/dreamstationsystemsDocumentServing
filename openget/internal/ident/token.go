// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 robinpie
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; version 2 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// Package ident implements identity without accounts: a token is 128 bits of
// crypto-random data, shown to the user in Crockford base32 and stored only
// as its SHA-256, so a leaked database yields nothing usable. There is no
// recovery path — losing the code loses the data, by design.
package ident

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
)

// TokenBits is the entropy in a token. 128 bits is far beyond guessable and still fits in a code a person can copy by hand.
const TokenBits = 128

// crockford is Crockford's base32 alphabet: no I, L, O or U, so the code cannot be misread as a different valid code and cannot spell anything unfortunate.
const crockford = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

// TokenLen is the encoded length: 128 bits at 5 bits per character.
const TokenLen = 26

var decodeMap = func() map[byte]byte {
	m := make(map[byte]byte, 40)
	for i := 0; i < len(crockford); i++ {
		c := crockford[i]
		m[c] = byte(i)
		if c >= 'A' && c <= 'Z' {
			m[c+32] = byte(i) // lower case
		}
	}
	// Crockford's documented confusables: I and L read as 1, O reads as 0.
	for _, p := range []struct {
		from byte
		to   byte
	}{{'I', '1'}, {'i', '1'}, {'L', '1'}, {'l', '1'}, {'O', '0'}, {'o', '0'}} {
		m[p.from] = m[p.to]
	}
	return m
}()

// Token is a plaintext token. It must never be written to a log or a database.
type Token string

// New mints a fresh token.
func New() (Token, error) {
	b := make([]byte, TokenBits/8)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("ident: entropy: %w", err)
	}
	return Token(encode(b)), nil
}

// encode renders 16 bytes as 26 Crockford base32 characters.
func encode(b []byte) string {
	var out strings.Builder
	out.Grow(TokenLen)
	var acc uint32
	var bits uint
	for _, c := range b {
		acc = acc<<8 | uint32(c)
		bits += 8
		for bits >= 5 {
			bits -= 5
			out.WriteByte(crockford[(acc>>bits)&31])
		}
	}
	if bits > 0 {
		out.WriteByte(crockford[(acc<<(5-bits))&31])
	}
	return out.String()
}

// ErrBadToken is returned when a code cannot be a token.
var ErrBadToken = errors.New("ident: not a valid restore code")

// Parse normalises a user-supplied code: case-insensitive, ignoring the grouping dashes and spaces we display it with, and folding Crockford's confusable characters. Returns the canonical uppercase form.
func Parse(s string) (Token, error) {
	var b strings.Builder
	b.Grow(TokenLen)
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == '-' || c == ' ' || c == '\t' {
			continue
		}
		v, ok := decodeMap[c]
		if !ok {
			return "", ErrBadToken
		}
		b.WriteByte(crockford[v])
	}
	if b.Len() != TokenLen {
		return "", ErrBadToken
	}
	return Token(b.String()), nil
}

// Hash is the storage form: SHA-256 of the canonical token, hex encoded.
//
// The database never sees plaintext, so a database leak — the realistic failure — does not hand anybody a working token.
func (t Token) Hash() string {
	sum := sha256.Sum256([]byte(t))
	return hex.EncodeToString(sum[:])
}

// Display groups the token for reading aloud or copying by hand:
//
//	4G7K-2M9P-XQ3R-8TWZ-VN5H-JD
func (t Token) Display() string {
	s := string(t)
	var b strings.Builder
	for i := 0; i < len(s); i += 4 {
		if i > 0 {
			b.WriteByte('-')
		}
		end := min(i+4, len(s))
		b.WriteString(s[i:end])
	}
	return b.String()
}

// String deliberately does NOT return the token.
//
// Tokens end up in structs that get logged, and %v on a struct would print the secret into the journal forever. Anything that genuinely needs the plaintext asks for it explicitly.
func (t Token) String() string { return "Token(redacted)" }

// Reveal returns the plaintext. Call only when handing it to the user.
func (t Token) Reveal() string { return string(t) }

// HashCert is the storage form for a Gemini client certificate fingerprint —
// Gemini's native identity mechanism, which unlike a cookie never appears in
// a URL, access log or referrer.
func HashCert(fingerprint string) string {
	sum := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(fingerprint))))
	return hex.EncodeToString(sum[:])
}
