// Synthetic tool-API regression; ES5 syntax for MuJS.
var pattern = new RegExp(new Array(34).join("[a]"));
if (!pattern.test(new Array(34).join("a")))
  throw new Error("33-class regexp failed");
var document = new PDFDocument(scriptArgs[0]);
var page = document.loadPage(0);
var text = page.toStructuredText().asText();
if (text.indexOf("REMOVE ME") < 0 || text.indexOf("KEEP TOTAL 123") < 0)
  throw new Error("Text extraction failed");
var matches = page.search("REMOVE ME");
if (matches.length !== 1)
  throw new Error("Unexpected search matches");
var quads = typeof matches[0][0] === "number" ? matches : matches[0];
var annotation = page.createAnnotation("Redact");
annotation.setQuadPoints(quads);
page.applyRedactions(false, 0, 0, 0);
document.save(scriptArgs[1], "garbage=4,compress");
var result = new PDFDocument(scriptArgs[1]);
var remaining = result.loadPage(0).toStructuredText().asText();
if (remaining.indexOf("REMOVE ME") >= 0 || remaining.indexOf("KEEP TOTAL 123") < 0)
  throw new Error("Redaction failed");
var fileSpec = result.getTrailer().get("Root").get("Names").get("EmbeddedFiles").get("Names").get(1);
var attachment = fileSpec.get("EF").get("F").readStream().asString();
if (attachment !== "<invoice>synthetic</invoice>")
  throw new Error("Attachment changed");
print("MuPDF regression passed");
