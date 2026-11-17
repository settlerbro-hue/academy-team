# Waiter standards and internship merge

Two separate curricula, RVB Minsk and 90-е (Pushkino, Khimki, Mytishchi), each retain the existing diary course ID, 17 lesson IDs and 18 diary test IDs. The old standards course and its four tests are unpublished, not deleted.

Unique standards questions move into the first three diary tests. Existing diary questions, IDs and keys stay unchanged. New pass thresholds and timers match the full new question counts. Old attempts keep their original snapshots, answer keys, answers, score, result and deadline.

Valid old standards passes can credit the corresponding new test. The service/check-back test needs both old passes. Old lesson marks credit the corresponding lesson; service/check-back needs both old lesson marks. No synthetic progress or attempts are inserted.

Trainee waiters retain the 17-lesson practice curriculum. Certified waiters and floor administrators receive three base lessons and three tests. Historical aliases resolve within the selected brand. Old result titles and unfinished attempts remain accessible.

Content corrections include the definition of precheck, flute description, current menu references instead of obsolete menu screenshots, agreed schedules and promotion conditions, separation of online knowledge checks from practical sign-off, and removal of repeated material. Practical tasks, floor plans, observation criteria and physical service illustrations remain.

Apply migration 047 and apply.sql together in one transaction after testing with ROLLBACK. apply.sql checks every reviewed updated_at and refuses to overwrite a course draft. It saves all previous records, private keys and affected histories to academy_private.audit_log and asserts that learning histories are byte-for-byte unchanged. The migration also checks and backs up the old training-status function. rollback.sql restores content, keys and the status function without deleting later progress or attempts.

Verification includes the full application check suite, production build, private backup tests, role/level and partial-progress regression cases, legacy AND/OR credits, pending attempt links, and database grading of correct and empty answers inside a rolled-back transaction.
