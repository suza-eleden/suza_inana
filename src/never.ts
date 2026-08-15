export function assertNever(value: never): never {
  throw new Error(`inalcanzable: ${String(value)}`);
}
