export enum EngineHostErrorCategory {
  PERMISSION_DENIED = 'permission_denied',
  INVALID_HANDLE = 'invalid_handle',
  UNAVAILABLE = 'unavailable',
  IO = 'io'
}

export class EngineHostError extends Error {
  category: EngineHostErrorCategory;
  operation: string;

  constructor(category: EngineHostErrorCategory, operation: string) {
    super('ENGINE_HOST_' + category.toUpperCase() + ':' + operation);
    this.name = 'EngineHostError';
    this.category = category;
    this.operation = operation;
  }
}
