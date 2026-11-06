// Build-time exporter for the pinned Hunspell sources; never loaded by the game.
// The build adds only a friend declaration to AffixMgr, so affix application,
// Unicode conditions, flags and final spelling validation remain Hunspell's.
#include <fstream>
#include <iostream>
#include <memory>
#include <set>
#include <string>
#include <vector>
#include "hunspell.hxx"
#include "hashmgr.hxx"
#include "affixmgr.hxx"
#include "affentry.hxx"

class ManiaWordExporter {
  Hunspell checker;
  std::vector<std::unique_ptr<HashMgr>> dictionaries;
  std::unique_ptr<AffixMgr> affixes;
  std::ofstream output;
  std::set<std::string> forms;

  using Flags = std::vector<unsigned short>;
  template<class Entry> static Flags continuation(Entry* entry, const Flags& other) {
    Flags result = entry->allowCross() ? other : Flags{};
    if (entry->getContLen()) result.insert(result.end(), entry->getCont(), entry->getCont() + entry->getContLen());
    return result;
  }
  void expand(const std::string& word, const Flags& prefixes, const Flags& suffixes, int np, int ns) {
    forms.insert(word);
    if (np < 1) for (auto flag : prefixes) {
      for (auto* rule = affixes->pFlag[flag & 255]; rule; rule = rule->getFlgNxt()) {
        if (rule->getFlag() != flag) continue;
        auto next = rule->add(word.data(), word.size());
        if (!next.empty()) expand(next, {}, continuation(rule, suffixes), np + 1, ns);
      }
    }
    if (ns < 2) for (auto flag : suffixes) {
      for (auto* rule = affixes->sFlag[flag & 255]; rule; rule = rule->getFlgNxt()) {
        if (rule->getFlag() != flag) continue;
        auto next = rule->add(word.data(), word.size());
        if (!next.empty()) {
          Flags next_suffixes;
          if (rule->getContLen()) next_suffixes.assign(rule->getCont(), rule->getCont() + rule->getContLen());
          expand(next, continuation(rule, prefixes), next_suffixes, np, ns + 1);
        }
      }
    }
  }
public:
  ManiaWordExporter(const char* aff, const char* dic, const char* target)
      : checker(aff, dic), output(target, std::ios::binary) {
    if (!output) throw std::runtime_error("Cannot open word-list output");
    dictionaries.emplace_back(new HashMgr(dic, aff));
    affixes.reset(new AffixMgr(aff, dictionaries));
    if (affixes->get_encoding() != "UTF-8" || affixes->get_complexprefixes())
      throw std::runtime_error("Exporter requires a UTF-8 dictionary without COMPLEXPREFIXES");
  }
  void run() {
    int column = -1;
    hentry* entry = nullptr;
    size_t roots = 0, count = 0;
    while ((entry = dictionaries.front()->walk_hashtable(column, entry))) {
      Flags flags;
      if (entry->alen) flags.assign(entry->astr, entry->astr + entry->alen);
      forms.clear();
      expand(entry->word, flags, flags, 0, 0);
      for (const auto& word : forms) if (checker.spell(word)) { output << word << '\n'; ++count; }
      ++roots;
    }
    output.flush();
    if (!output) throw std::runtime_error("Cannot write word-list output");
    std::cerr << roots << " roots, " << count << " accepted forms before global deduplication\n";
  }
};

int main(int argc, char** argv) {
  try {
    if (argc != 4) throw std::runtime_error("Usage: typing-hunspell-export dictionary.aff dictionary.dic output.txt");
    ManiaWordExporter(argv[1], argv[2], argv[3]).run();
    return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
