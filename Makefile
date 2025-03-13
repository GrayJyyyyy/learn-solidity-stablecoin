lcov:
	forge coverage --report lcov && genhtml lcov.info -o coverage-report && open coverage-report/index.html