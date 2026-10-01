/**
 * Helper: compute month range as { start, end } date strings.
 * end is the first day of the next month (exclusive upper bound).
 */
function getMonthRange(month) {
  const [year, mon] = month.split('-').map(Number);
  const start = `${month}-01`;
  const nextMonth = mon === 12
    ? `${year + 1}-01`
    : `${year}-${String(mon + 1).padStart(2, '0')}`;
  const end = `${nextMonth}-01`;
  return { start, end };
}

module.exports = { getMonthRange };
