// 职责: 测试封面默认提示词、点击追加碎片与参考图截断。
// 关联文件:
//   lib/shared/services/cover_prompt_builder.dart
//   lib/shared/models/cover_brief.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/cover_brief.dart';
import 'package:reveric/shared/services/cover_prompt_builder.dart';

CoverBrief buildBrief() => CoverBrief(
  category: '历史 · 群像',
  style: '水墨写意',
  palette: '墨与宣',
  temperature: '冷灰为底，暖色只留给灯与印章',
  figure: '没有单一主角，建议以意象替代具体人物',
  era: '明末江南，避开现代器物与现代字体',
  motifs: const [
    CoverBriefMotif(text: '江面与渔火', from: '第 3 章 夜泊'),
    CoverBriefMotif(text: '空舟系岸', from: '第 17 章 别渡'),
  ],
  readAt: DateTime(2026, 8, 11, 14, 20),
  sources: [
    CoverBriefSource(chapterId: 'c1', updatedAt: DateTime(2026, 8, 1)),
    CoverBriefSource(chapterId: 'c2', updatedAt: DateTime(2026, 8, 2)),
  ],
  chapterCount: 42,
  wordCount: 184000,
);

void main() {
  group('defaultCoverPrompt', () {
    test('默认分行写作品名与作者名，不含简介', () {
      final prompt = defaultCoverPrompt(novelTitle: '南渡记', authorName: '柳三变');

      expect(
        prompt,
        '你是一个专业的网文封面设计师，请设计一个有吸引力的封面，适合于番茄等平台。\n'
        '作品名：南渡记\n'
        '作者名：柳三变',
      );
      expect(prompt, isNot(contains('作品简介：')));
      expect(prompt, isNot(contains('禁止：')));
      expect(prompt, isNot(contains('构图：')));
      expect(prompt, isNot(contains('品类：')));
    });

    test('书名或作者为空时用占位', () {
      final prompt = defaultCoverPrompt(novelTitle: '  ', authorName: '');

      expect(prompt, contains('作品名：（未填）'));
      expect(prompt, contains('作者名：（未填）'));
      expect(prompt, isNot(contains('作品简介：')));
    });
  });

  group('append snippets', () {
    test('风格 / 色调 / 构图各自成一句可追加的碎片', () {
      expect(coverStyleSnippet('水墨写意'), '风格：水墨写意。');
      expect(coverPaletteSnippet('ink'), '色调：墨与宣。');
      expect(coverCompositionSnippet('留白构图'), '构图：留白构图，主体偏一侧，留出大片可放文字的暗部。');
    });

    test('档案字段、简介与意象可追加，空值跳过', () {
      expect(coverBriefFieldSnippet('品类', '历史 · 群像'), '品类：历史 · 群像。');
      expect(coverBriefFieldSnippet('品类', '  '), '');
      expect(coverSynopsisSnippet('明末江南的一段旧事。'), '作品简介：明末江南的一段旧事。');
      expect(coverSynopsisSnippet('  '), '');
      expect(coverMotifSnippet(buildBrief().motifs.first), '意象：「江面与渔火」。');
    });

    test('追加不重复，空碎片不变', () {
      const base = '你是一个专业的网文封面设计师。';
      expect(appendCoverPromptFragment(base, '风格：水墨写意。'), '$base\n风格：水墨写意。');
      expect(
        appendCoverPromptFragment('$base\n风格：水墨写意。', '风格：水墨写意。'),
        '$base\n风格：水墨写意。',
      );
      expect(appendCoverPromptFragment(base, '   '), base);
    });
  });

  group('finalizeCoverPrompt', () {
    test('下发的正文就是用户提示词本身，参考图不追加任何说明', () {
      expect(finalizeCoverPrompt(userPrompt: '画一张封面'), '画一张封面');
    });

    test('首尾空白被裁掉', () {
      expect(finalizeCoverPrompt(userPrompt: '  画一张封面\n'), '画一张封面');
    });
  });

  group('isCoverBriefStale', () {
    test('稿子没动时不过时', () {
      final brief = buildBrief();

      expect(
        isCoverBriefStale(
          brief,
          CoverBriefStats(
            chapterCount: 42,
            wordCount: 184000,
            sourceUpdatedAt: {
              'c1': DateTime(2026, 8, 1),
              'c2': DateTime(2026, 8, 2),
            },
          ),
        ),
        isFalse,
      );
    });

    test('读过的章节被改了就过时 —— 体量没变也算', () {
      final brief = buildBrief();

      expect(
        isCoverBriefStale(
          brief,
          CoverBriefStats(
            chapterCount: 42,
            wordCount: 184000,
            sourceUpdatedAt: {'c1': DateTime(2026, 8, 9)},
          ),
        ),
        isTrue,
      );
    });

    test('后面又写了 5 章就过时', () {
      final brief = buildBrief();

      expect(
        isCoverBriefStale(
          brief,
          const CoverBriefStats(chapterCount: 46, wordCount: 184000),
        ),
        isFalse,
      );
      expect(
        isCoverBriefStale(
          brief,
          const CoverBriefStats(chapterCount: 47, wordCount: 184000),
        ),
        isTrue,
      );
    });

    test('字数涨两成就过时，差一点则不提示', () {
      final brief = buildBrief();

      // 184000 * 1.2 = 220800，卡在阈值两侧各验一次。
      expect(
        isCoverBriefStale(
          brief,
          const CoverBriefStats(chapterCount: 42, wordCount: 220000),
        ),
        isFalse,
      );
      expect(
        isCoverBriefStale(
          brief,
          const CoverBriefStats(chapterCount: 42, wordCount: 221000),
        ),
        isTrue,
      );
    });
  });

  group('出图参数落在上游可接受范围内', () {
    // 4K 档曾经出 3072x4096：单边和总像素双双超过 gpt-image-2 的上限，
    // 请求会被直接拒。每个档位都验一遍，避免再加档时重蹈覆辙。
    test('每个分辨率档位都不超过 gpt-image-2 的边长与像素上限', () {
      for (final resolution in coverResolutions) {
        final size = coverImageSize(coverRatios.first, resolution);
        final parts = size.split('x');
        final width = int.parse(parts[0]);
        final height = int.parse(parts[1]);

        expect(width % 16, 0, reason: '$size 宽不是 16 的倍数');
        expect(height % 16, 0, reason: '$size 高不是 16 的倍数');
        expect(width, lessThanOrEqualTo(3840), reason: '$size 宽超边长上限');
        expect(height, lessThanOrEqualTo(3840), reason: '$size 高超边长上限');
        expect(
          width * height,
          inInclusiveRange(655360, 8294400),
          reason: '$size 总像素超出上游允许区间',
        );
      }
    });

    // auto 档让模型自选质量，同一档位在不同画布上落到不同的 output token 量级，
    // 用量就难以按质量档位比较。所有档位必须是显式值。
    test('质量档位全部显式下发，默认档在列表内', () {
      expect(coverQualities.map((item) => item.id), isNot(contains('auto')));
      for (final quality in coverQualities) {
        expect(quality.apiValue, isNotEmpty);
      }
      expect(coverQualityOf(coverDefaultQualityId).id, coverDefaultQualityId);
    });

    test('旧批次存的 auto 回落到默认档而不是第一档', () {
      expect(coverQualityOf('auto').id, coverDefaultQualityId);
    });
  });
}
