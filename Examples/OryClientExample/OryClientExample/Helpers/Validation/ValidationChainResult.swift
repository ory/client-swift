public enum ValidationChainResult<Output> {
    case next(output: Output, errors: [Error])
    case `break`(errors: [Error])
}
