class LyricsGenerationResult {
  const LyricsGenerationResult.success(this.text)
    : errorMessage = null,
      isSuccess = true;

  const LyricsGenerationResult.failure(this.errorMessage)
    : text = null,
      isSuccess = false;

  final String? text;
  final String? errorMessage;
  final bool isSuccess;
}
