export function theme_color(style: CSSStyleDeclaration, name: string) {
  const color = style.getPropertyValue(`--color-${name}`);
  if (!color) return undefined;
  return `hsl(${color.split(' ').join(',')})`;
}
