// 职责: Demo 小说初始化 — 首次启动或空库时创建示例小说，覆盖各种数据类型供用户探索
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/utils/storage_paths.dart
//   lib/shared/utils/text_unit_count.dart
//   lib/desktop/pages/home.dart

import 'package:drift/drift.dart';
import 'package:reveric/shared/models/asset_purpose.dart';
import 'package:flutter/services.dart';

import '../database/app_database.dart';
import '../database/novel_content_database.dart';
import '../models/content_status.dart';
import '../models/outline_draft.dart';
import '../utils/random_id.dart';
import '../utils/text_unit_count.dart';
import '../utils/short_entity_id.dart';
import '../utils/short_entity_id_allocator.dart';
import '../logger/app_logger.dart';
import 'novel_content.dart';
import 'image_library_service.dart';

const _demoChapterOneContent = '''柜台上的水位尺升到第三格时，沈砚开始退信。

地址淹了的，收件人搬走的，还有一封只写着“卖鱼女人收”。他把最后一封夹进明天的邮袋，没有盖退件章。码头上卖鱼的女人有十一位，总能问到。

屋后忽然响了一声。

不是敲门。声音来自墙里的铜信槽。沈砚抬头看了看钟，六点差一刻，旧街的邮管停用已经七年。风吹进管道也会响，他早习惯了，可这次响声很短，像有人在另一端用指节试了试。

他拿起接信的木盘，等了片刻。一只信封滑出来，撞在盘沿。

信封干得出奇。邮局的地板常年返潮，连他袖口都是湿的，这只信封却像刚从火炉旁拿下。上面没有地址，背面盖着一枚红色私章，右下角缺了一小块。

沈砚把盘子搁下，去抽屉里翻母亲的旧收据。抽屉卡住了，他拉了两次才打开。那枚章在最后一张收据上也缺着同样的角，缺口穿过“兰”字的末笔。

沈兰。他已经七年没在新纸上见过这个名字。

窗外有人喊他收桥。沈砚应了一声，声音却轻得自己都没听清。他把信封举向灯，里面没有信纸，只有一道细长的影子。他不敢拆，又觉得这个念头可笑：给别人的信才不能拆，没写地址的信，规矩里根本没有这一条。

门被推开，收桥的船工探进半个身子：“再不走，你今晚就睡柜台上。”

“这条管子通到哪里？”

船工顺着他的目光看见铜槽，笑意没了。“原先通旧街。”

“现在呢？”

“现在通海里。”

沈砚将信封压在收据下，拿起门后的撑桥杆。两人把浮桥抬高一孔，水已经漫过下面一级石阶。护城灯从雾里扫来，照出水面上一片微小的亮点。灯鳗贴着桩脚游，细得像散开的线头。

“今年来得早。”船工说。

沈砚问是不是涨潮要提前。船工摇头，说灯鳗吃盐，又不看潮历，接着催他锁门。他答应了，却一直等脚步声走远，才回到柜台。

信封背面多了一行灰字。

不是墨，更像被什么东西啃去了纸的表层，只剩下落笔时压出的沟。他侧过灯罩，逐字辨认。

旧街，槐树巷，十七号。

母亲最后工作的那间邮局。

沈砚用拇指摩挲封口。红蜡里夹着一粒蓝色结晶，在灯下不亮，移到暗处却幽幽泛光。他认得普通灯盐，没有见过这种蓝色。信封里那道细影忽然挪了一下，一只指甲盖大小的螺从纸缝爬出，落在柜台上。

他赶紧拿玻璃杯罩住。螺壳半透明，腹部有一道墨黑。

信上的地址曾经存在，只是被吃掉了。

钟敲了六下。往常这时，潮水会在石阶前停一阵，再缓缓退下去。今天水却越过第三格，继续朝第四格爬。柜台下面先湿了一条线，随后一枚没收好的邮票浮了起来。

沈砚捡起邮票，关掉柜台灯，把信封和旧收据分别装进油布袋。他没有把母亲的名字念出来，仿佛声音太大，就会惊动信的另一端。

出门前，他翻过歇业牌，在背面写了几个字：去修灯铺，明早回。

写完他停了一会儿，又把“明早”划掉。

浮桥尽头，叶棠那艘废船还亮着灯。沈砚踩过湿木板，身后铜信槽又响了一声。这一次，他没有回头。''';

const _demoChapterTwoContent = '''叶棠正替一只灯罩换铆钉。沈砚上船时，她没抬头，只把脚边的水桶踢过去。

“漏水自己接。灯明天取。”

“我不修灯。”

“那就别踩我的线。”

沈砚低头，鞋底下横着一根细铜丝，另一端连着窗边的听筒。他小心跨过去，把油布袋放在检验台上。叶棠见到红蜡，锤子在半空停住。

“谁给你的？”

“邮管送来的。”

她放下锤子，先把台上的铁屑扫干净，又从柜子里取出一片白瓷。沈砚想催，她已经用镊子夹住封口脱落的一小粒蓝盐，放在瓷片上，滴下一滴水。

盐没化。水珠倒缩小了，像被里面的东西喝掉。

“灯塔的。”她说。

“能从旧街寄出来吗？”

“管子没断，就能。可他们说旧街的管子早断了。”

叶棠把灯罩侧过来，让光贴着信封扫过去。槐树巷十七号下面还有字，笔画相互压着。她换了三次角度，拿一张薄纸覆上去，用炭条轻擦。沈砚站得太近，挡住了光，她用手背推了推他的肩。

纸上浮出两个字：退回。

“这是退信？”沈砚说。

“至少有人想让它看起来像退信。”

他从袋里取出母亲的旧收据，指给她看缺角。叶棠没有马上接话。她找了一把尺，量完两枚印，又对着灯看了封蜡的边缘。

“章是一枚章。盖章的人，不一定是一个人。”

沈砚将收据收回去。纸角折了一下，他用指甲反复压平。

叶棠蹲下，从桌腿底下抽出一叠账纸。桌子顿时歪了，瓷片里的水流向边缘。她拿半块木头塞回去，把账纸铺在两人中间。

每页都记着日期和灯盐用量，其中一列被红笔圈了起来。

“旧街没人了，为什么这些年还在往下送蓝盐？”

“养灯鳗？”

“灯鳗可不会签收。”

最下面那页有一个模糊手印。沈砚将灯移近，发现手印旁写着槐树巷的编号，日期却是上个月。他伸手去拿，叶棠按住纸边。

“原件不离开我。”

“我带你认路。”

“你七年没下去。”

“门牌还认得。”

船底传来两下闷响，铜听筒在窗台上滚了一寸。叶棠抓住它，贴到左耳，抬手示意沈砚别动。过了一会儿，她放下听筒，开始往工具袋里塞气阀和短绳。

“闸门关早了。今晚只剩西侧检修口。”

沈砚问她怎么知道。她把铜丝从窗外收进来，末端系着一小截浸湿的木片。

“平时有三道回声。现在少一道。”

他们下船时，码头已经拉上绳索。灯务署的人正在挂封锁牌，理由是大潮检修。沈砚隔着人群看见裴铎，署长站在伞下，衣领干燥，手里握着一只银怀表。

一个船工问，低处还有人没回来，能不能再等半刻。

裴铎合上怀表：“等他们回来，桥上这些人怎么办？”

没人再说话。挂绳索的人绕过船工，把最后一端拴紧。

叶棠拉着沈砚退进两座货棚之间。他刚要开口，她已将一盏罩好黑布的小灯递给他。工具袋里露着那叠账纸，纸边用夹子扣牢。

“先说好。”她说，“看见气管别碰。要开阀，叫我。”

“看见邮件呢？”

她看了他一眼：“你拿。”

沈砚将灯塞进外衣，沿西边石阶往下走。最下一级还露着，上面嵌着半块旧门牌。他蹲下来，擦去牌上的泥，认出一个模糊的“槐”字。

门牌的箭头朝下，指向漆黑的水。''';

const _demoChapterTitles = <String>[
  '盐印下的名字',
  '退潮后的街道',
  '灯塔不收回信',
  '被卖掉的黎明',
  '最后一班邮船',
];

const _demoChapterOutlines = <String>[
  '沈砚带着空白信封到修灯铺求证。叶棠用斜光照出被刮掉的退信地址，又发现封蜡里混着灯塔专用的蓝盐。两人在闸口见到灯务署的封锁令，决定赶在大潮前进入旧街。',
  '沈砚和叶棠随退潮进入水下旧街，循邮袋上的刻痕找到废弃分拣室。被宣告淹死的居民仍住在气室里，靠灯塔抽走他们的记忆换取空气；沈砚母亲留下的投递簿证明交易并非自愿。沈砚与叶棠用笔迹和盐印试出回潮辨址术，也察觉它会夺走声音记忆。',
  '灯务署长裴铎截下邮船，提出用母亲的去向换投递簿。沈砚假意答应，叶棠从检修通道潜入，发现灯塔每夜向上城出售旧街居民的记忆，维持护城灯的只是其中很小一部分。',
  '裴铎提前放潮封住旧街出口。沈砚以回潮辨址术定位失散居民，付出失去母亲声音的代价。叶棠组织修灯匠改接气室，浮桥会接应；众人带着原始账页赶到灯塔晨间拍卖场。',
  '沈砚在公开验灯时投递全部账页，迫使灯务署停止抽取记忆。裴铎交出主闸钥匙接受审讯。旧街居民迁上浮桥，沈砚从母亲的最后一封信得知她早已死于抢修；他与叶棠重开潮汐邮局，为活人送信。',
];

Future<String> createDemoNovel(
  AppDatabase database, {
  ShortEntityIdBuilder idBuilder = buildShortEntityId,
}) async {
  final existingNovel =
      await (database.select(database.novels)..where(
            (table) =>
                table.title.equals('潮汐邮局') &
                table.deletedAt.equals(notDeletedSentinel),
          ))
          .getSingleOrNull();
  if (existingNovel != null) {
    return existingNovel.id;
  }

  final novelId = idBuilder(ShortEntityIdType.novel);
  final now = DateTime.now();

  String? coverAssetId;
  try {
    final data = await rootBundle.load('assets/images/demo/novel_cover.webp');
    coverAssetId = (await buildImageLibraryService(database).importBytes(
      data.buffer.asUint8List(),
      name: 'novel_cover.webp',
      novelId: novelId,
      purpose: AssetPurpose.cover,
    )).id;
  } catch (_) {
    // asset not found, leave the cover empty
  }

  await database.novelDao.create(
    id: novelId,
    title: '潮汐邮局',
    description:
        '雾港的邮差从不接收没有地址的信。沈砚却收到一只写着母亲姓名的空信封，而她已随旧街沉入海底七年。为了送出这封退信，他和修灯匠叶棠踏进退潮才显露的街巷，发现整座城的灯火，都有人在水下付账。',
    coverAssetId: coverAssetId,
    tags: const ['奇幻', '悬疑', '冒险', '群像', 'demo'],
    category: '奇幻',
  );

  final contentDatabasePath = await buildNovelContentDatabasePath(novelId);
  final contentDatabase = NovelContentDatabase(contentDatabasePath);
  await contentDatabase.seedDefaultWorkspace(
    includeInitialChapter: true,
    idBuilder: idBuilder,
  );
  Future<String> insertEntity(
    ShortEntityIdType type,
    String tableName,
    Future<void> Function(String id) insert,
  ) async {
    String? attemptedId;
    try {
      return await insertWithShortEntityId(
        type: type,
        tableName: tableName,
        buildId: idBuilder,
        idExists: (id) async =>
            await contentDatabase
                .customSelect(
                  'SELECT 1 FROM $tableName WHERE id = ? LIMIT 1',
                  variables: [Variable.withString(id)],
                )
                .getSingleOrNull() !=
            null,
        insert: (id) {
          attemptedId = id;
          return insert(id);
        },
      );
    } catch (error, stackTrace) {
      AppLogger.forModule('DemoNovel').error(
        '[DB] $tableName INSERT failed, id=$attemptedId',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  await NovelContentService(
    contentDatabase,
    idBuilder: idBuilder,
  ).outlineService.createOutline(defaultTitle: '旧街来信');

  // --- Existing chapter 1 is already created by seedDefaultWorkspace, update its title ---
  final seededChapters = await contentDatabase.chapterDao.getAll();
  if (seededChapters.isNotEmpty) {
    final chapter1 = seededChapters.first;
    await (contentDatabase.update(
      contentDatabase.chapters,
    )..where((c) => c.id.equals(chapter1.id))).write(
      ChaptersCompanion(
        content: const Value(_demoChapterOneContent),
        wordCount: Value(countTextUnits(_demoChapterOneContent)),
        title: const Value('没有地址的信'),
        outline: Value(
          '潮汐邮局关门前，沈砚收到一封无地址的退信，封口印着失踪母亲的私章。信封背面显出水下旧街的街名，邮局外的潮水却正在逆着钟声上涨。沈砚带信去找能辨认旧灯盐印的叶棠。',
        ),
      ),
    );
  }

  // Chapters 2-6
  for (var i = 2; i <= 6; i++) {
    await insertEntity(
      ShortEntityIdType.chapter,
      'chapter_nodes',
      (id) async => contentDatabase.chapterDao.insert(
        ChaptersCompanion.insert(
          id: id,
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: i,
          title: Value(_demoChapterTitles[i - 2]),
          outline: Value(_demoChapterOutlines[i - 2]),
          content: Value(i == 2 ? _demoChapterTwoContent : ''),
          wordCount: Value(i == 2 ? countTextUnits(_demoChapterTwoContent) : 0),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      ),
    );
  }

  // Characters
  final shenYanId = await insertEntity(
    ShortEntityIdType.character,
    'character_profiles',
    (id) async => contentDatabase
        .into(contentDatabase.characterProfiles)
        .insert(
          CharacterProfilesCompanion.insert(
            id: id,
            name: '沈砚',
            role: const Value(characterRoleProtagonist),
            gender: const Value(characterGenderMale),
            biography: const Value(
              '雾港邮差，七年前失去在旧街邮局工作的母亲。他靠替人送信维生，熟悉每条浮桥，却始终拒接通往旧街的邮件。一只带母亲私章的信封让他第一次越过封锁线。',
            ),
            description: const Value(
              '二十六岁，肩窄手长，旧邮袋的肩带缝过三次。说话习惯先问门牌再问姓名。遇事会反复核对收据，害怕自己签下一个再也无法兑现的承诺。',
            ),
            sortOrder: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  final yeTangId = await insertEntity(
    ShortEntityIdType.character,
    'character_profiles',
    (id) async => contentDatabase
        .into(contentDatabase.characterProfiles)
        .insert(
          CharacterProfilesCompanion.insert(
            id: id,
            name: '叶棠',
            role: const Value(characterRoleSupporting),
            gender: const Value(characterGenderFemale),
            biography: const Value(
              '修灯匠，曾在灯务署做学徒，因质疑旧街耗盐账被除名。她靠修民用灯谋生，暗中记录灯塔每夜的耗盐量，想找出师父背负事故罪名的证据。',
            ),
            description: const Value(
              '二十四岁，袖口常留着蓝盐结晶，右耳听力受损，交谈时会把左侧转向对方。擅长辨认灯罩上的细微刻痕，不相信没有留下原件的口头保证。',
            ),
            sortOrder: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  final peiDuoId = await insertEntity(
    ShortEntityIdType.character,
    'character_profiles',
    (id) async => contentDatabase
        .into(contentDatabase.characterProfiles)
        .insert(
          CharacterProfilesCompanion.insert(
            id: id,
            name: '裴铎',
            role: const Value(characterRoleAntagonist),
            gender: const Value(characterGenderMale),
            biography: const Value(
              '灯务署长，七年前组织封闭旧街气室，此后以护城灯不能熄灭为由持续抽取居民记忆。他把临时避险变成了生意，也把当年的救援者变成了终身债户。',
            ),
            description: const Value(
              '四十八岁，衣领一丝不乱，随身带一只已经停走的怀表。谈判时从不提高声音，先讲全城的难处，再让某一个人承担代价。',
            ),
            sortOrder: const Value(2),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // Locations
  await insertEntity(
    ShortEntityIdType.location,
    'locations',
    (id) async => contentDatabase
        .into(contentDatabase.locations)
        .insert(
          LocationsCompanion.insert(
            id: id,
            name: '潮汐邮局',
            description: const Value(
              '建在浮桥桩顶的木屋，水位尺钉在柜台旁。后墙保留着旧街邮局的铜信槽，沉街之后再未开启，直到那只无地址信封从里面落下。',
            ),
            type: const Value(locationTypeBuilding),
            tags: const Value('雾港,邮局,浮桥'),
            sortOrder: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.location,
    'locations',
    (id) async => contentDatabase
        .into(contentDatabase.locations)
        .insert(
          LocationsCompanion.insert(
            id: id,
            name: '沈砚的阁楼',
            description: const Value(
              '邮局楼上的窄阁楼，窗外能看见护城灯。沈砚把母亲的旧邮帽放在干燥的锡盒里，屋内唯一的新家具是给未领邮件做的格架。',
            ),
            type: const Value(locationTypeBuilding),
            tags: const Value('住所,邮局'),
            sortOrder: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.location,
    'locations',
    (id) async => contentDatabase
        .into(contentDatabase.locations)
        .insert(
          LocationsCompanion.insert(
            id: id,
            name: '叶棠修灯铺',
            description: const Value(
              '废船改成的修理铺，船腹吊着不同年份的灯罩。窗边一张带刻度的检验台用于辨认盐印，桌腿下压着叶棠从灯务署带出的旧账副本。',
            ),
            type: const Value(locationTypeBuilding),
            tags: const Value('修灯,证据,码头'),
            sortOrder: const Value(2),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // Items: Faction
  final deliveryTeamId = await insertEntity(
    ShortEntityIdType.faction,
    'items',
    (id) async => contentDatabase
        .into(contentDatabase.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            type: entityTypeFaction,
            title: '潮汐投递队',
            content: const Value(
              '沈砚为进入旧街发起的临时投递队，由叶棠负责路线与灯具。两人约定邮件与证人一并带回，途中不以任何人的记忆抵付通行费。',
            ),
            status: const Value(itemEntryStatusActive),
            sortOrder: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // Items: Skill
  final tideAddressSkillId = await insertEntity(
    ShortEntityIdType.skill,
    'items',
    (id) async => contentDatabase
        .into(contentDatabase.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            type: entityTypeSkill,
            title: '回潮辨址术',
            content: const Value(
              '沈砚将邮路记忆与叶棠的盐印测向法结合，自创沿回潮定位收件人的方法；叶棠也掌握了操作。施术者必须见过收件人的笔迹，每使用一次会永久失去一段自己珍视的声音记忆，不能找回已死之人。',
            ),
            status: const Value(itemEntryStatusActive),
            sortOrder: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // --- More Factions ---
  final bridgeGuildId = await insertEntity(
    ShortEntityIdType.faction,
    'items',
    (id) async => contentDatabase
        .into(contentDatabase.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            type: entityTypeFaction,
            title: '浮桥会',
            content: const Value(
              '雾港船工、邮差与修灯匠组成的互助行会，沈砚和叶棠都在会内登记。成员以轮班修桥换取停泊位，大潮时负责接应被困在低处的居民。',
            ),
            status: const Value(itemEntryStatusActive),
            sortOrder: const Value(3),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.faction,
    'items',
    (id) async => contentDatabase
        .into(contentDatabase.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            type: entityTypeFaction,
            title: '灯务署',
            content: const Value(
              '掌管护城灯、闸门和灯盐配给的机构，由裴铎主持。公开收入来自灯费，秘密收入来自出售旧街居民的记忆；多数基层修灯匠只知道前一项。',
            ),
            status: const Value(itemEntryStatusActive),
            sortOrder: const Value(4),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // --- 潮路技能 ---
  final saltReadingSkillId = await insertEntity(
    ShortEntityIdType.skill,
    'items',
    (id) async => contentDatabase
        .into(contentDatabase.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            type: entityTypeSkill,
            title: '辨盐',
            content: const Value(
              '凭盐晶颜色、粒径和溶解速度区分民用灯盐与灯塔蓝盐。必须保留原样并做对照，受污的盐只能缩小来源范围，不能直接认定持有人。',
            ),
            status: const Value(itemEntryStatusActive),
            sortOrder: const Value(2),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  final tideListeningSkillId = await insertEntity(
    ShortEntityIdType.skill,
    'items',
    (id) async => contentDatabase
        .into(contentDatabase.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            type: entityTypeSkill,
            title: '听潮测路',
            content: const Value(
              '先辨明管道盐源，再用铜听筒比较气室间的回声，推算退潮时可通行的路径。测量只在当前潮段有效，闸门变动后需要重测。',
            ),
            status: const Value(itemEntryStatusActive),
            sortOrder: const Value(3),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  final navigationSkillId = await insertEntity(
    ShortEntityIdType.skill,
    'items',
    (id) async => contentDatabase
        .into(contentDatabase.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            type: entityTypeSkill,
            title: '逆潮引航',
            content: const Value(
              '结合听潮测路与回潮辨址术，在涨潮中为多人寻找气室间的通路。只能使用仍连通的管道，不能穿越封死的闸门；每次定位仍须承担辨址术的记忆代价。',
            ),
            status: const Value(itemEntryStatusActive),
            sortOrder: const Value(4),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // --- Creatures / Species ---
  await insertEntity(
    ShortEntityIdType.creature,
    'items',
    (id) async => contentDatabase
        .into(contentDatabase.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            type: entityTypeCreature,
            title: '灯鳗',
            content: const Value(
              '以灯盐为食的小型鳗鱼，身体透光，迁游路线会随蓝盐浓度改变。旧街居民用它们检验漏气管道，灯务署则把异常聚集称作季节现象。',
            ),
            status: const Value(itemEntryStatusActive),
            sortOrder: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.creature,
    'items',
    (id) async => contentDatabase
        .into(contentDatabase.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            type: entityTypeCreature,
            title: '噬墨螺',
            content: const Value(
              '附着在潮湿纸面上的小螺，吃掉墨迹却留下凹痕。受害文书可借斜光读取压痕，但无法据此复原原本的墨色和落笔时间。',
            ),
            status: const Value(itemEntryStatusActive),
            sortOrder: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // --- Entity Relations ---
  // Character ↔ Faction
  await insertEntity(
    ShortEntityIdType.relation,
    'entity_relations',
    (id) async => contentDatabase
        .into(contentDatabase.entityRelations)
        .insert(
          EntityRelationsCompanion.insert(
            id: id,
            sourceType: entityTypeCharacter,
            sourceId: shenYanId,
            targetType: entityTypeFaction,
            targetId: deliveryTeamId,
            relationType: characterFactionFounder,
            sortOrder: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.relation,
    'entity_relations',
    (id) async => contentDatabase
        .into(contentDatabase.entityRelations)
        .insert(
          EntityRelationsCompanion.insert(
            id: id,
            sourceType: entityTypeCharacter,
            sourceId: yeTangId,
            targetType: entityTypeFaction,
            targetId: deliveryTeamId,
            relationType: characterFactionLeader,
            sortOrder: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.relation,
    'entity_relations',
    (id) async => contentDatabase
        .into(contentDatabase.entityRelations)
        .insert(
          EntityRelationsCompanion.insert(
            id: id,
            sourceType: entityTypeCharacter,
            sourceId: shenYanId,
            targetType: entityTypeFaction,
            targetId: bridgeGuildId,
            relationType: characterFactionMember,
            sortOrder: const Value(2),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.relation,
    'entity_relations',
    (id) async => contentDatabase
        .into(contentDatabase.entityRelations)
        .insert(
          EntityRelationsCompanion.insert(
            id: id,
            sourceType: entityTypeCharacter,
            sourceId: yeTangId,
            targetType: entityTypeFaction,
            targetId: bridgeGuildId,
            relationType: characterFactionMember,
            sortOrder: const Value(3),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.relation,
    'entity_relations',
    (id) async => contentDatabase
        .into(contentDatabase.entityRelations)
        .insert(
          EntityRelationsCompanion.insert(
            id: id,
            sourceType: entityTypeCharacter,
            sourceId: peiDuoId,
            targetType: entityTypeFaction,
            targetId: deliveryTeamId,
            relationType: characterFactionEnemy,
            sortOrder: const Value(4),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // Character ↔ Skill
  await insertEntity(
    ShortEntityIdType.relation,
    'entity_relations',
    (id) async => contentDatabase
        .into(contentDatabase.entityRelations)
        .insert(
          EntityRelationsCompanion.insert(
            id: id,
            sourceType: entityTypeCharacter,
            sourceId: shenYanId,
            targetType: entityTypeSkill,
            targetId: tideAddressSkillId,
            relationType: characterSkillCreator,
            sortOrder: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.relation,
    'entity_relations',
    (id) async => contentDatabase
        .into(contentDatabase.entityRelations)
        .insert(
          EntityRelationsCompanion.insert(
            id: id,
            sourceType: entityTypeCharacter,
            sourceId: yeTangId,
            targetType: entityTypeSkill,
            targetId: tideAddressSkillId,
            relationType: characterSkillMastered,
            sortOrder: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // Skill ↔ Skill (prerequisite chain)
  await insertEntity(
    ShortEntityIdType.relation,
    'entity_relations',
    (id) async => contentDatabase
        .into(contentDatabase.entityRelations)
        .insert(
          EntityRelationsCompanion.insert(
            id: id,
            sourceType: entityTypeSkill,
            sourceId: saltReadingSkillId,
            targetType: entityTypeSkill,
            targetId: tideListeningSkillId,
            relationType: skillSkillPrerequisite,
            sortOrder: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.relation,
    'entity_relations',
    (id) async => contentDatabase
        .into(contentDatabase.entityRelations)
        .insert(
          EntityRelationsCompanion.insert(
            id: id,
            sourceType: entityTypeSkill,
            sourceId: tideListeningSkillId,
            targetType: entityTypeSkill,
            targetId: navigationSkillId,
            relationType: skillSkillPrerequisite,
            sortOrder: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.relation,
    'entity_relations',
    (id) async => contentDatabase
        .into(contentDatabase.entityRelations)
        .insert(
          EntityRelationsCompanion.insert(
            id: id,
            sourceType: entityTypeSkill,
            sourceId: tideAddressSkillId,
            targetType: entityTypeSkill,
            targetId: navigationSkillId,
            relationType: skillSkillBranch,
            sortOrder: const Value(2),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // --- Worldbuilding: 历史年表 ---
  await insertEntity(
    ShortEntityIdType.loreDocument,
    'documents',
    (id) async => contentDatabase
        .into(contentDatabase.documents)
        .insert(
          DocumentsCompanion.insert(
            id: id,
            type: documentTypeLore,
            title: '雾港沉街年表',
            content: const Value(
              '## 七年前\n旧街防潮闸损坏，居民转入气室避难。沈砚的母亲在抢修邮路时遇难，裴铎随后封闭旧街，将幸存者列入失踪名单。\n\n## 六年前至今\n灯务署以供气为条件收取记忆，逐步把抽取量提高到维生需要之外。叶棠发现耗盐账异常，被逐出灯务署。\n\n## 本次大潮\n旧街居民利用残存邮管送出退信。沈砚与叶棠入城取证，揭露交易，并在大潮封路前组织撤离。',
            ),
            status: const Value(documentStatusActive),
            sortOrder: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // --- Worldbuilding: 世界设定总览 ---
  await insertEntity(
    ShortEntityIdType.loreDocument,
    'documents',
    (id) async => contentDatabase
        .into(contentDatabase.documents)
        .insert(
          DocumentsCompanion.insert(
            id: id,
            type: documentTypeLore,
            title: '潮水与记忆',
            content: const Value(
              '## 雾港\n浮桥连接高地与船屋，旧街沉在港湾浅底，每月大潮前有短暂露出路面的窗口。气室由灯塔管道供气。\n\n## 灯盐\n普通灯盐储光，蓝盐还能吸附人的声音记忆。灯塔只需少量蓝盐维持护城灯，过量抽取用于出售记忆。\n\n## 代价\n被抽取的声音记忆无法归还，文书可以记录事实，却不能代替一个人的亲身记忆。邮件不会来自未来，死者也不能借信复生。',
            ),
            status: const Value(documentStatusActive),
            sortOrder: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // --- Worldbuilding: 职业体系 ---
  await insertEntity(
    ShortEntityIdType.loreDocument,
    'documents',
    (id) async => contentDatabase
        .into(contentDatabase.documents)
        .insert(
          DocumentsCompanion.insert(
            id: id,
            type: documentTypeLore,
            title: '雾港营生',
            content: const Value(
              '## 邮差\n识路、验封、留收据。无地址邮件须由邮差自行承担退件费用。\n\n## 修灯匠\n负责灯盐、气阀与光路维护，需要同时保留试样和检修记录。\n\n## 船工\n按潮位调整浮桥，替居民运水和迁屋，熟悉气室上方的锚点。\n\n## 灯务官\n登记灯费并批准闸门开闭。批准权集中在署长手中，是旧街难以求援的原因。',
            ),
            status: const Value(documentStatusActive),
            sortOrder: const Value(2),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // Foreshadowing
  await insertEntity(
    ShortEntityIdType.foreshadowing,
    'foreshadowings',
    (id) async => contentDatabase
        .into(contentDatabase.foreshadowings)
        .insert(
          ForeshadowingsCompanion.insert(
            id: id,
            title: '封蜡里的蓝盐',
            setup: const Value(
              '第一章里，信封私章的缺角与母亲旧章一致，但封蜡里混有灯塔专用的蓝盐。第二章叶棠确认盐源，提示寄件人仍与灯塔管道相通。',
            ),
            payoff: const Value(''),
            status: const Value(foreshadowingStatusPlanted),
            sortOrder: const Value(0),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  await insertEntity(
    ShortEntityIdType.foreshadowing,
    'foreshadowings',
    (id) async => contentDatabase
        .into(contentDatabase.foreshadowings)
        .insert(
          ForeshadowingsCompanion.insert(
            id: id,
            title: '停在四点的怀表',
            setup: const Value(
              '裴铎的怀表始终停在四点。他声称这是旧街沉没的时间，投递簿却记录四点之后仍有人接收救援邮件，证明封街决定发生在确认幸存者之后。',
            ),
            payoff: const Value(''),
            status: const Value(foreshadowingStatusPlanted),
            sortOrder: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  // AgentRules
  await contentDatabase
      .into(contentDatabase.agentRules)
      .insert(
        AgentRulesCompanion.insert(
          id: buildRandomId('agent_rule'),
          name: '叙事与感官',
          content:
              '采用贴近沈砚的第三人称叙事。通过水位、灯盐、潮湿纸面等可触摸的细节呈现危险；人物不知道的证据不由旁白提前解释。对话保留职业习惯，避免用长篇独白讲设定。',
          enabled: const Value(true),
          sortOrder: const Value(0),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

  await contentDatabase
      .into(contentDatabase.agentRules)
      .insert(
        AgentRulesCompanion.insert(
          id: buildRandomId('agent_rule'),
          name: '奇幻边界',
          content:
              '邮件不能穿越时间，死者不能复生。回潮辨址术必须以真实笔迹为引，每次定位都失去一段声音记忆；不能在危急时刻临时取消代价。气室、闸门和邮管的连通关系须与既有路线一致。',
          enabled: const Value(true),
          sortOrder: const Value(1),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

  await contentDatabase
      .into(contentDatabase.agentRules)
      .insert(
        AgentRulesCompanion.insert(
          id: buildRandomId('agent_rule'),
          name: '人物选择',
          content:
              '沈砚遇到风险先考虑邮件能否送达，叶棠先查证据能否复核，裴铎先计算秩序的成本。让三人用行动暴露各自的盲点，叶棠有独立的查账目标，不只承担解释设定的职责。',
          enabled: const Value(true),
          sortOrder: const Value(2),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

  await contentDatabase
      .into(contentDatabase.agentRules)
      .insert(
        AgentRulesCompanion.insert(
          id: buildRandomId('agent_rule'),
          name: '章节推进',
          content: '每章完成一个具体行动并留下它造成的新难题。正文不复述章纲，不以预告或写作说明收尾；尚未展开的章节只保留大纲。',
          enabled: const Value(true),
          sortOrder: const Value(3),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

  // Outline enrichment - update the existing outline document
  final existingOutlineRecord = await (contentDatabase.select(
    contentDatabase.outlines,
  )..where((o) => o.deletedAt.equals(notDeletedSentinel))).getSingleOrNull();
  if (existingOutlineRecord != null) {
    await (contentDatabase.update(
      contentDatabase.outlines,
    )..where((o) => o.documentId.equals(existingOutlineRecord.documentId))).write(
      const OutlinesCompanion(
        content: Value(
          '第一卷：旧街来信（六章）\n第一章：没有地址的信。沈砚接到不可能送达的退件，决定验封。\n第二章：盐印下的名字。叶棠辨出灯塔蓝盐，两人发现封锁令。\n第三章：退潮后的街道。旧街幸存者交出投递簿，求援信的来源揭晓。\n第四章：灯塔不收回信。裴铎提出交易，叶棠找到记忆买卖账目。\n第五章：被卖掉的黎明。大潮提前，沈砚付出记忆代价，众人带证据撤离。\n第六章：最后一班邮船。账页公开，裴铎交出闸钥，邮局重新开张。',
        ),
        status: Value(outlineStatusInProgress),
      ),
    );
  }

  // Material document: character relationships
  await insertEntity(
    ShortEntityIdType.materialsDocument,
    'documents',
    (id) async => contentDatabase
        .into(contentDatabase.documents)
        .insert(
          DocumentsCompanion.insert(
            id: id,
            type: documentTypeMaterial,
            title: '投递队关系备忘',
            content: const Value(
              '## 沈砚与叶棠\n两人都属浮桥会。沈砚发起投递队，叶棠负责路线与检修；一个想尽快救人，一个坚持先查明供气系统，争执来自风险判断不同。\n\n## 沈砚与裴铎\n裴铎掌握母亲死亡的记录，试图用私情换走公开证据。沈砚最终拒绝把其他居民的名字换成自己的答案。\n\n## 叶棠与裴铎\n前学徒与署长的权力差距仍在。叶棠用可复核的账页争取船工支持，不靠对方突然认错。',
            ),
            status: const Value(documentStatusActive),
            sortOrder: const Value(2),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        ),
  );

  final chapterStats = await contentDatabase.chapterDao.getListStats();
  await contentDatabase.close();

  try {
    await database.novelDao.updateWordCount(
      id: novelId,
      wordCount: chapterStats.totalWordCount,
    );
  } catch (error, stackTrace) {
    AppLogger.forModule('DemoNovel').error(
      '[DB] novels UPDATE word_count failed, id=$novelId',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }

  await database.novelDao.updateContentDatabasePath(
    id: novelId,
    contentDatabasePath: contentDatabasePath,
  );

  return novelId;
}
