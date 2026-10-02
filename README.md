# Smart Quiz V4.3.5

## Question bank CSV export/import

Teacher Question Bank now supports:
- Exporting the teacher's complete question bank to `questions.csv`.
- Importing the same CSV after editing in Excel.
- Existing questions are updated when `questionId` is present.
- New questions are created when `questionId` is empty.
- Import validates teacher ownership and subject assignment.
- `questionUnit` is updated together with the question.
- `questionKeys` is updated for automatic/manual answer data.
- Invalid rows are skipped and reported after import.

Supported types: `single_choice`, `multiple_choice`, `true_false`, `essay`, `ordering`.
