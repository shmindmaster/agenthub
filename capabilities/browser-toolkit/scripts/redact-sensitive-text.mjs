export function redactSensitiveText(value) {
  return String(value)
    .replace(/Bearer\s+[A-Za-z0-9._~+\/-]+=*/gi, "Bearer <redacted>")
    .replace(/((?:proxy-authorization|authorization|set-cookie|cookie|x-api-key)["']?\s*[:=]\s*)[^\r\n]*/gim, "$1<redacted>");
}
