// eslint-disable-next-line @typescript-eslint/no-namespace
export namespace localJsonStorage {
  export function get<T>(key: string): T | null {
    const value = localStorage.getItem(key);
    return value ? JSON.parse(value) : null;
  }

  export function set<T>(key: string, value: T) {
    localStorage.setItem(key, JSON.stringify(value));
  }
}
