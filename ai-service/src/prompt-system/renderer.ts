const PLACEHOLDER_PATTERN = /\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g;

export function renderTemplate(
  template: string,
  variables: Record<string, unknown>,
): string {
  return template.replace(PLACEHOLDER_PATTERN, (_match, key: string) => {
    const value = variables[key];

    if (value == null) {
      return '';
    }

    if (typeof value === 'string') {
      return value;
    }

    return JSON.stringify(value, null, 2);
  });
}
