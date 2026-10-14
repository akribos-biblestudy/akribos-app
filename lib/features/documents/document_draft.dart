/// The acknowledged server text and local text are separate. A response to an
/// earlier save must not erase keystrokes entered while that save was in flight.
class DocumentDraft {
  DocumentDraft({
    required this.title,
    required this.markdown,
    required this.revision,
  }) : _savedTitle = title,
       _savedMarkdown = markdown;

  String title;
  String markdown;
  int revision;
  String _savedTitle;
  String _savedMarkdown;

  bool get dirty => title != _savedTitle || markdown != _savedMarkdown;

  Map<String, dynamic> snapshot() => {
    'title': title,
    'markdown': markdown,
    'revision': revision,
  };

  void acknowledge(Map<String, dynamic> submitted, int nextRevision) {
    _savedTitle = submitted['title'] as String;
    _savedMarkdown = submitted['markdown'] as String;
    revision = nextRevision;
  }

  void discard() {
    title = _savedTitle;
    markdown = _savedMarkdown;
  }
}
