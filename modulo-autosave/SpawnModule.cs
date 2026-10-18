// Spawn fixo por mapa (o Unturned sem plugins nao tem "setspawn"). Comandos (chat de admin com "/", ou console/painel):
//   setspawn                    -> no chat: usa a sua posicao
//   setspawn <jogador>          -> usa a posicao do jogador
//   setspawn <x> <y> <z> [giro] -> coordenadas
//   delspawn                    -> volta aos spawns normais do mapa
//   verspawn                    -> mostra o spawn atual
//   irspawn [jogador|todos]     -> leva jogador(es) ao spawn agora
// Com o spawn definido, quem entra pela primeira vez e quem renasce depois de morrer vai para ele.
// Quem renasce na propria cama continua na cama, a menos que UT_SPAWN_CAMA=0.
// Fica salvo em Servers\Principal\Level\<mapa>\setspawn.txt (entra nos backups do mapa).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using SDG.Unturned;
using Steamworks;
using UnityEngine;

namespace UtAutosave
{
    public class SpawnFixo : MonoBehaviour
    {
        public static SpawnFixo Instancia;
        public static bool Definido;
        public static Vector3 Posicao;
        public static float Giro;

        private static string mapaCarregado;
        private bool registrado;
        private bool respeitaCama;
        private readonly List<KeyValuePair<float, Player>> pendentes = new List<KeyValuePair<float, Player>>();

        private void Awake()
        {
            Instancia = this;
            respeitaCama = Environment.GetEnvironmentVariable("UT_SPAWN_CAMA") != "0";
            PlayerLife.OnRevived_Global += AoRenascer;
            Provider.onEnemyConnected += AoConectar;
        }

        private void OnDestroy()
        {
            PlayerLife.OnRevived_Global -= AoRenascer;
            Provider.onEnemyConnected -= AoConectar;
        }

        private void Update()
        {
            if (!Level.isLoaded) { mapaCarregado = null; return; }
            if (!registrado)
            {
                // Registra so com o mapa carregado: a lista de comandos do jogo ja existe nessa hora
                registrado = true;
                Commander.register(new CmdSetSpawn());
                Commander.register(new CmdDelSpawn());
                Commander.register(new CmdVerSpawn());
                Commander.register(new CmdIrSpawn());
                Commander.register(new CmdJogador("player"));
                Commander.register(new CmdJogador("jogador"));
                Commander.register(new CmdTeleporte("tp"));
                Commander.register(new CmdTeleporte("teleportar"));
                Painel.ListaPronta = true;   // depois de registrar todos, para a lista do painel sair completa
                ModeConfigData cfg = Provider.modeConfigData;
                CommandWindow.Log(string.Format(CultureInfo.InvariantCulture,
                    "[Config] Zumbis Spawn_Chance={0} | Skills: Lose_Skills_PvE={1} Lose_Skills_PvP={2} Skillset_Prevents_Skill_Loss={3} Spawn_With_Max_Skills={4} Spawn_With_Stamina_Skills={5} Prevent_Level_Skill_Overrides={6}",
                    cfg.Zombies.Spawn_Chance, cfg.Players.Lose_Skills_PvE, cfg.Players.Lose_Skills_PvP, cfg.Players.Skillset_Prevents_Skill_Loss,
                    cfg.Players.Spawn_With_Max_Skills, cfg.Players.Spawn_With_Stamina_Skills, cfg.Players.Prevent_Level_Skill_Overrides));
            }
            if (mapaCarregado != Level.info.name) { mapaCarregado = Level.info.name; Carregar(); }
            float agora = Time.realtimeSinceStartup;
            for (int i = pendentes.Count - 1; i >= 0; i--)
            {
                if (agora < pendentes[i].Key) continue;
                Player p = pendentes[i].Value;
                pendentes.RemoveAt(i);
                if (Definido && p != null && p.life != null && !p.life.isDead) Teleportar(p);
            }
        }

        private void AoConectar(SteamPlayer sp)
        {
            // Sem Player.dat neste mapa = primeira vez do jogador aqui
            if (!Definido || sp == null || sp.player == null) return;
            if (!PlayerSavedata.fileExists(sp.playerID, "/Player/Player.dat")) Agendar(sp.player, 1f);
        }

        private void AoRenascer(PlayerLife vida)
        {
            if (!Definido || vida == null || vida.player == null) return;
            Player p = vida.player;
            if (respeitaCama)
            {
                Vector3 cama; byte angulo;
                if (BarricadeManager.tryGetBed(p.channel.owner.playerID.steamID, out cama, out angulo) &&
                    (p.transform.position - cama).sqrMagnitude < 10f * 10f) return;   // escolheu renascer na cama
            }
            Agendar(p, 0.5f);
        }

        private void Agendar(Player p, float atraso)
        {
            pendentes.Add(new KeyValuePair<float, Player>(Time.realtimeSinceStartup + atraso, p));
        }

        public static void Teleportar(Player p)
        {
            p.teleportToLocationUnsafe(Posicao + Vector3.up * 0.5f, Giro);
        }

        // ---------- Arquivo ----------
        private static string Arquivo()
        {
            string dir = Environment.GetEnvironmentVariable("UT_PAINEL_DIR");
            string save = !string.IsNullOrEmpty(dir) ? Directory.GetParent(dir).FullName
                : Path.Combine(Path.Combine(Environment.CurrentDirectory, "Servers"), Provider.serverID);
            return Path.Combine(Path.Combine(Path.Combine(save, "Level"), Level.info.name), "setspawn.txt");
        }

        private static void Carregar()
        {
            Definido = false;
            try
            {
                string arq = Arquivo();
                if (!File.Exists(arq)) return;
                string[] v = File.ReadAllText(arq).Trim().Split(';');
                Posicao = new Vector3(F(v[0]), F(v[1]), F(v[2]));
                Giro = v.Length > 3 ? F(v[3]) : 0f;
                Definido = true;
                CommandWindow.Log("[Spawn] Spawn fixo deste mapa: " + Texto());
            }
            catch (Exception e) { CommandWindow.LogError("[Spawn] Falha ao ler o spawn: " + e.Message); }
        }

        public static void Definir(Vector3 pos, float giro)
        {
            Posicao = pos; Giro = giro; Definido = true;
            string arq = Arquivo();
            Directory.CreateDirectory(Path.GetDirectoryName(arq));
            File.WriteAllText(arq, string.Join(";", new[] { S(pos.x), S(pos.y), S(pos.z), S(giro) }));
        }

        public static void Remover()
        {
            Definido = false;
            string arq = Arquivo();
            if (File.Exists(arq)) File.Delete(arq);
        }

        public static string Texto()
        {
            return Definido ? string.Format(CultureInfo.InvariantCulture, "{0:0.0} {1:0.0} {2:0.0} (giro {3:0})", Posicao.x, Posicao.y, Posicao.z, Giro) : "nenhum";
        }

        private static float F(string s) { return float.Parse(s.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture); }
        private static string S(float f) { return f.ToString("0.###", CultureInfo.InvariantCulture); }
    }

    // ---------- Comandos ----------
    public abstract class CmdSpawnBase : Command
    {
        protected CmdSpawnBase(string nome, string info, string ajuda)
        {
            localization = new Local();
            _command = nome; _info = info; _help = ajuda;
        }

        protected static void Responder(CSteamID quem, string msg, bool erro = false)
        {
            if (erro) CommandWindow.LogWarning("[Spawn] " + msg); else CommandWindow.Log("[Spawn] " + msg);
            if (quem != CSteamID.Nil && PlayerTool.getPlayer(quem) != null) ChatManager.say(quem, msg, erro ? Color.red : Color.green);
        }

        protected static Player Achar(string nome)
        {
            SteamPlayer sp;
            return PlayerTool.tryGetSteamPlayer(nome, out sp) && sp != null ? sp.player : null;
        }

        protected static bool Pronto(CSteamID quem)
        {
            if (Level.isLoaded) return true;
            Responder(quem, "O mapa ainda esta carregando.", true);
            return false;
        }
    }

    public class CmdSetSpawn : CmdSpawnBase
    {
        public CmdSetSpawn() : base("setspawn", "Define o spawn fixo do mapa", "setspawn [jogador | x y z [giro]]") { }

        protected override void execute(CSteamID quem, string parametro)
        {
            if (!Pronto(quem)) return;
            string p = (parametro ?? "").Trim();
            string[] partes = p.Split(new[] { ' ', ',', ';', '/' }, StringSplitOptions.RemoveEmptyEntries);
            float x, y, z, giro = 0f;
            if (partes.Length >= 3 && Num(partes[0], out x) && Num(partes[1], out y) && Num(partes[2], out z))
            {
                if (partes.Length > 3) Num(partes[3], out giro);
                SpawnFixo.Definir(new Vector3(x, y, z), giro);
            }
            else
            {
                Player alvo = p.Length > 0 ? Achar(p) : PlayerTool.getPlayer(quem);
                if (alvo == null)
                {
                    Responder(quem, p.Length > 0 ? "Jogador '" + p + "' nao encontrado." : "Use: setspawn <jogador> ou setspawn <x> <y> <z> (no chat, setspawn sozinho usa a sua posicao).", true);
                    return;
                }
                SpawnFixo.Definir(alvo.transform.position, alvo.look.yaw);
            }
            Responder(quem, "Spawn fixo definido em " + SpawnFixo.Texto() + ".");
        }

        private static bool Num(string s, out float f) { return float.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out f); }
    }

    public class CmdDelSpawn : CmdSpawnBase
    {
        public CmdDelSpawn() : base("delspawn", "Remove o spawn fixo do mapa", "delspawn") { }

        protected override void execute(CSteamID quem, string parametro)
        {
            if (!Pronto(quem)) return;
            SpawnFixo.Remover();
            Responder(quem, "Spawn fixo removido; voltam os spawns normais do mapa.");
        }
    }

    public class CmdVerSpawn : CmdSpawnBase
    {
        public CmdVerSpawn() : base("verspawn", "Mostra o spawn fixo do mapa", "verspawn") { }

        protected override void execute(CSteamID quem, string parametro)
        {
            if (!Pronto(quem)) return;
            Responder(quem, "Spawn fixo: " + SpawnFixo.Texto());
        }
    }

    public class CmdIrSpawn : CmdSpawnBase
    {
        public CmdIrSpawn() : base("irspawn", "Leva jogador(es) ao spawn fixo", "irspawn [jogador | todos]") { }

        protected override void execute(CSteamID quem, string parametro)
        {
            if (!Pronto(quem)) return;
            if (!SpawnFixo.Definido) { Responder(quem, "Nenhum spawn fixo definido (use setspawn).", true); return; }
            string p = (parametro ?? "").Trim();
            if (p.Equals("todos", StringComparison.OrdinalIgnoreCase) || p.Equals("all", StringComparison.OrdinalIgnoreCase))
            {
                int n = 0;
                foreach (SteamPlayer sp in Provider.clients)
                    if (sp.player != null && !sp.player.life.isDead) { SpawnFixo.Teleportar(sp.player); n++; }
                Responder(quem, n + " jogador(es) levado(s) ao spawn.");
                return;
            }
            Player alvo = p.Length > 0 ? Achar(p) : PlayerTool.getPlayer(quem);
            if (alvo == null) { Responder(quem, p.Length > 0 ? "Jogador '" + p + "' nao encontrado." : "Use: irspawn <jogador> ou irspawn todos.", true); return; }
            SpawnFixo.Teleportar(alvo);
            Responder(quem, alvo.channel.owner.playerID.characterName + " foi levado ao spawn.");
        }
    }
}
