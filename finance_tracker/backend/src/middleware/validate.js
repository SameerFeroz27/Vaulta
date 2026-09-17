function validate(schema, source = 'body') {
  return async (req, res, next) => {
    try {
      const validatedData = await schema.parseAsync(req[source]);
      req[source] = validatedData;
      next();
    } catch (err) {
      next(err);
    }
  };
}

module.exports = validate;
