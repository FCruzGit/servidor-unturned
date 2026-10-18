// Comando "tp" / "teleportar": leva um jogador (ou todos) ate outro jogador, ao spawn fixo, a um local do mapa ou a coordenadas.
//   tp <jogador> <destino>        destino = jogador | spawn | nome de local (cidade) | x y z
//   tp todos <destino>
//   tp <destino>                  (no chat de admin: leva voce)
// Nomes com espaco funcionam: o comando testa as divisoes possiveis. Tambem aceita "tp <jogador>/<destino>".
using System;
using System.Collections.Generic;
using System.Globalization;
using SDG.Unturned;
using Steamworks;
using UnityEngine;

namespace UtAutosave
{
    public class CmdTeleporte : Command
    {
        public CmdTeleporte(string nome)
        {
            localization = new Local();
            _command = nome;
            _info = "Teleporta um jogador ate outro jogador, spawn, local ou coordenadas";
            _help = nome + " <jogador|todos> <jogador|spawn|local|x y z>";
        }

        private struct Destino { public Vector3 Pos; public float Giro; public string Nome; }

        protected override void execute(CSteamID quem, string parametro)
        {
            if (!Level.isLoaded) { Responder(quem, "O mapa ainda esta carregando.", true); return; }
            string p = (parametro ?? "").Trim();
            if (p.Length == 0) { Responder(quem, "Use: " + _help, true); return; }

            List<Player> origem = null;
            Destino destino = new Destino();
            bool achou = false;

            if (p.Contains("/"))
            {
                int i = p.IndexOf('/');
                achou = Origem(p.Substring(0, i).Trim(), out origem) && Alvo(p.Substring(i + 1).Trim(), out destino);
            }
            else
            {
                string[] palavras = p.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                for (int i = 1; i < palavras.Length && !achou; i++)
                {
                    string esq = string.Join(" ", palavras, 0, i), dir = string.Join(" ", palavras, i, palavras.Length - i);
                    achou = Origem(esq, out origem) && Alvo(dir, out destino);
                }
                // So o destino: leva quem digitou (chat)
                if (!achou && PlayerTool.getPlayer(quem) != null && Alvo(p, out destino))
                {
                    origem = new List<Player> { PlayerTool.getPlayer(quem) };
                    achou = true;
                }
            }

            if (!achou)
            {
                Responder(quem, "Nao entendi '" + p + "'. Os jogadores precisam estar online. Use: " + _help, true);
                return;
            }

            int n = 0;
            foreach (Player o in origem)
            {
                if (o == null || o.life.isDead) continue;

                o.teleportToLocationUnsafe(destino.Pos, destino.Giro);
                n++;
            }
            string quemFoi = origem.Count == 1 ? origem[0].channel.owner.playerID.characterName : n + " jogador(es)";
            Responder(quem, quemFoi + " teleportado(s) para " + destino.Nome + ".", false);
        }

        private static bool Origem(string s, out List<Player> lista)
        {
            lista = new List<Player>();
            if (s.Equals("todos", StringComparison.OrdinalIgnoreCase) || s.Equals("all", StringComparison.OrdinalIgnoreCase))
            {
                foreach (SteamPlayer sp in Provider.clients) if (sp.player != null) lista.Add(sp.player);
                return lista.Count > 0;
            }
            Player p = Jogador(s);
            if (p != null) lista.Add(p);
            return p != null;
        }

        private static bool Alvo(string s, out Destino d)
        {
            d = new Destino();
            if (s.Length == 0) return false;

            Player p = Jogador(s);
            if (p != null)
            {
                // Um pouco ao lado, para nao ficar um dentro do outro
                d.Pos = p.transform.position - p.transform.forward * 1.5f + Vector3.up * 0.3f;
                d.Giro = p.look.yaw;
                d.Nome = p.channel.owner.playerID.characterName;
                return true;
            }
            if (s.Equals("spawn", StringComparison.OrdinalIgnoreCase))
            {
                if (!SpawnFixo.Definido) return false;
                d.Pos = SpawnFixo.Posicao + Vector3.up * 0.5f; d.Giro = SpawnFixo.Giro; d.Nome = "o spawn fixo";
                return true;
            }
            string[] c = s.Split(new[] { ' ', ',', ';' }, StringSplitOptions.RemoveEmptyEntries);
            float x, y, z;
            if (c.Length == 3 && Num(c[0], out x) && Num(c[1], out y) && Num(c[2], out z))
            {
                d.Pos = new Vector3(x, y, z); d.Nome = string.Format(CultureInfo.InvariantCulture, "{0:0.0} {1:0.0} {2:0.0}", x, y, z);
                return true;
            }
            // Local nomeado do mapa (igual primeiro, depois "contem")
            LocationDevkitNode achado = null;
            try
            {
                foreach (LocationDevkitNode n in LocationDevkitNodeSystem.Get().GetAllNodes())
                {
                    if (n == null || string.IsNullOrEmpty(n.locationName)) continue;
                    if (n.locationName.Equals(s, StringComparison.OrdinalIgnoreCase)) { achado = n; break; }
                    if (achado == null && n.locationName.IndexOf(s, StringComparison.OrdinalIgnoreCase) >= 0) achado = n;
                }
            }
            catch (Exception) { }
            if (achado == null) return false;
            Vector3 pos = achado.transform.position;
            RaycastHit hit;   // pousa no chao
            if (Physics.Raycast(new Vector3(pos.x, 1024f, pos.z), Vector3.down, out hit, 2048f, RayMasks.BLOCK_COLLISION)) pos = hit.point + Vector3.up * 0.5f;
            d.Pos = pos; d.Nome = achado.locationName;
            return true;
        }

        private static Player Jogador(string s)
        {
            SteamPlayer sp;
            return PlayerTool.tryGetSteamPlayer(s, out sp) && sp != null ? sp.player : null;
        }

        private static bool Num(string s, out float f) { return float.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out f); }

        private static void Responder(CSteamID quem, string msg, bool erro)
        {
            if (erro) CommandWindow.LogWarning("[Teleporte] " + msg); else CommandWindow.Log("[Teleporte] " + msg);
            if (quem != CSteamID.Nil && PlayerTool.getPlayer(quem) != null) ChatManager.say(quem, msg, erro ? Color.red : Color.cyan);
        }
    }
}
