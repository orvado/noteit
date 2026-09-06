import Foundation

/// Programming languages that ship with a built-in snippet pack, in the
/// "most popular" order the packs are presented in.
enum Language: String, CaseIterable, Codable, Identifiable, Hashable {
    case python, javascript, java, csharp, cpp, typescript, sql, go, rust, kotlin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .python: return "Python"
        case .javascript: return "JavaScript"
        case .java: return "Java"
        case .csharp: return "C#"
        case .cpp: return "C/C++"
        case .typescript: return "TypeScript"
        case .sql: return "SQL"
        case .go: return "Go"
        case .rust: return "Rust"
        case .kotlin: return "Kotlin"
        }
    }

    /// Lower-cased file extensions that map to this language.
    var fileExtensions: [String] {
        switch self {
        case .python: return ["py", "pyw"]
        case .javascript: return ["js", "mjs", "cjs", "jsx"]
        case .java: return ["java"]
        case .csharp: return ["cs", "csx"]
        case .cpp: return ["c", "h", "cpp", "cc", "cxx", "hpp", "hh", "hxx", "ino"]
        case .typescript: return ["ts", "tsx", "mts", "cts"]
        case .sql: return ["sql"]
        case .go: return ["go"]
        case .rust: return ["rs"]
        case .kotlin: return ["kt", "kts", "ktm"]
        }
    }

    /// The pack's built-in snippets (~30 per language). A private copy is
    /// seeded the first time a pack is enabled; user edits then diverge.
    var builtInSnippets: [TextSnippet] {
        switch self {
        case .python: return LanguagePackSnippets.python
        case .javascript: return LanguagePackSnippets.javascript
        case .java: return LanguagePackSnippets.java
        case .csharp: return LanguagePackSnippets.csharp
        case .cpp: return LanguagePackSnippets.cpp
        case .typescript: return LanguagePackSnippets.typescript
        case .sql: return LanguagePackSnippets.sql
        case .go: return LanguagePackSnippets.go
        case .rust: return LanguagePackSnippets.rust
        case .kotlin: return LanguagePackSnippets.kotlin
        }
    }

    /// Short representative snippet used by the syntax-theme preview in
    /// Settings (and handy for manual testing).
    var sampleCode: String {
        switch self {
        case .python:
            return """
            import math

            def circle_area(radius: float) -> float:
                \"\"\"Return the area of a circle.\"\"\"
                if radius < 0:
                    raise ValueError("radius must be >= 0")
                return math.pi * radius ** 2

            print(circle_area(2.5))  # ~19.63
            """
        case .javascript:
            return """
            import { fetchUser } from "./api.js";

            async function greet(id) {
              const user = await fetchUser(id);
              // fall back for missing names
              const name = user?.name ?? "stranger";
              return `Hello, ${name}!`;
            }

            console.log(greet(42));
            """
        case .java:
            return """
            import java.util.List;

            public final class Greeter {
                private static final String PREFIX = "Hello";

                public static String greet(List<String> names) {
                    // join with commas, or greet the world
                    return PREFIX + ", " + String.join(", ", names) + "!";
                }
            }
            """
        case .csharp:
            return """
            using System.Linq;

            namespace Demo {
                public static class Greeter {
                    static string Greet(string name) =>
                        $"Hello, {name}!"; // interpolation

                    public static void Run() {
                        var names = new[] { "Ada", "Ken" };
                        names.Select(Greet).ToList();
                    }
                }
            }
            """
        case .cpp:
            return """
            #include <stdio.h>
            #include "util.h"

            #define MAX_USERS 100

            typedef struct { int id; char name[32]; } User;

            int main(int argc, char *argv[]) {
                User u = { 1, "Ada" };
                /* greet the user */
                printf("Hello, %s!\\n", u.name);
                return 0;
            }
            """
        case .typescript:
            return """
            interface User { name: string; age: number }

            function oldest(users: User[]): User | null {
              let best: User | null = null;
              for (const u of users) {
                if (best === null || u.age > best.age) best = u;
              }
              return best;
            }
            """
        case .sql:
            return """
            CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                name VARCHAR(80) NOT NULL
            );

            SELECT u.name, COUNT(*) AS total
            FROM users u
            JOIN orders o ON o.user_id = u.id  -- joined rows
            WHERE u.created_at > '2026-01-01'
            GROUP BY u.name ORDER BY total DESC LIMIT 10;
            """
        case .go:
            return """
            package main

            import "fmt"

            // Point is a 2D coordinate.
            type Point struct{ X, Y float64 }

            func main() {
                p := Point{X: 1.5, Y: -2}
                fmt.Printf("(%v, %v)\\n", p.X, p.Y)
            }
            """
        case .rust:
            return """
            use std::collections::HashMap;

            /// Count how often each word appears.
            fn word_counts(text: &str) -> HashMap<&str, usize> {
                let mut counts = HashMap::new();
                for word in text.split_whitespace() {
                    *counts.entry(word).or_insert(0) += 1;
                }
                counts
            }
            """
        case .kotlin:
            return """
            data class User(val name: String, val age: Int = 0)

            fun oldest(users: List<User>): User? =
                users.maxByOrNull { it.age }  // null when empty

            fun main() {
                val team = listOf(User("Ada", 36), User("Ken", 41))
                println("Oldest: ${'$'}{oldest(team)?.name ?: "none"}")
            }
            """
        }
    }

    /// Lower-cased markers used to guess the language from document content
    /// (only consulted for unsaved documents). Markers are chosen to be
    /// distinctive across the pack languages.
    var contentMarkers: [String] {
        switch self {
        case .python:
            return ["def ", "elif ", "self.", "print(", "__name__", "lambda ", "#!/usr/bin/env python"]
        case .javascript:
            return ["function ", "const ", "=>", "console.log", "require(", "document.", "module.exports", "export default", "usestate", "async "]
        case .java:
            return ["public class", "system.out.", "import java.", "@override", "string[] args", "private void"]
        case .csharp:
            return ["console.writeline", "using system", "get; set;", "namespace ", "console.read", "static void main"]
        case .cpp:
            return ["#include", "int main(", "printf(", "std::", "malloc(", "#define", "nullptr"]
        case .typescript:
            return [": string", ": number", ": boolean", "interface ", "readonly ", "implements ", " as const"]
        case .sql:
            return ["select ", "insert into", "create table", " group by", "order by", "join ", "primary key", "alter table", "delete from", "distinct"]
        case .go:
            return ["package ", "func ", ":=", "fmt.", "if err != nil", "go func", "import ("]
        case .rust:
            return ["fn ", "let mut", "impl ", "use std::", "&str", "match ", "pub fn"]
        case .kotlin:
            return ["fun ", "val ", "when ", "companion object", "?:", "lateinit", "suspend fun"]
        }
    }

    // MARK: Detection

    static func fromFileExtension(_ ext: String) -> Language? {
        let e = ext.lowercased()
        guard !e.isEmpty else { return nil }
        return allCases.first { $0.fileExtensions.contains(e) }
    }

    /// Guesses the language from text content. Best-effort heuristic for
    /// unsaved documents: the highest-scoring language needs at least 2
    /// distinct marker hits totalling 3+ so plain prose (notes!) doesn't
    /// trip a pack.
    static func detect(fromContent text: String) -> Language? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let sample = String(trimmed.prefix(10_000)).lowercased()

        func score(_ markers: [String]) -> Int {
            markers.reduce(0) { $0 + min(sample.ranges(of: $1).count, 3) }
        }
        func distinct(_ markers: [String]) -> Int {
            markers.filter { sample.contains($0) }.count
        }

        // JavaScript is only considered when nothing else qualified — every
        // TypeScript source also matches the JavaScript markers, so TS must
        // get first claim.
        var best: (lang: Language, score: Int)?
        for lang in allCases where lang != .javascript {
            let markers = lang.contentMarkers
            let s = score(markers)
            if s >= 3, distinct(markers) >= 2, s > (best?.score ?? 0) {
                best = (lang, s)
            }
        }
        if let best { return best.lang }
        let js = Language.javascript.contentMarkers
        if score(js) >= 3, distinct(js) >= 2 { return .javascript }
        return nil
    }
}
