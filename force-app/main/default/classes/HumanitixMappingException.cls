/**
 * Thrown when the mapping configuration is invalid (bad object/field references)
 * or a record cannot be mapped. Fails fast with a clear, admin-actionable message.
 */
public with sharing class HumanitixMappingException extends Exception {}
