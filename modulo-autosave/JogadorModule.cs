// Comando "player <nome>" (ou "jogador <nome>"): mostra os dados e as coordenadas de um jogador online.
// No chat de admin, "/player" sozinho mostra os seus.
using System;
using System.Collections.Generic;
using System.Globalization;
using SDG.Unturned;
using Steamworks;
using UnityEngine;

namespace UtAutosave
{
    public class CmdJogador : Command
    {
        public CmdJogador(string nome)
        {
            localization = new Local();
            _command = nome;
            _info = "Mostra dados e coordenadas de um jogador";
            _help = nome + " <jogador>";
        }

        protected override void execute(CSteamID quem, string parametro)
        {
            string p = (parametro ?? "").Trim();
            Player alvo = null;
            if (p.Length > 0)
            {
                SteamPlayer sp;
                if (PlayerTool.tryGetSteamPlayer(p, out sp) && sp != null) alvo = sp.player;
            }
            else alvo = PlayerTool.getPlayer(quem);

            if (alvo == null)
            {
                Responder(quem, new List<string> { p.Length > 0 ? "Jogador '" + p + "' nao encontrado (precisa estar online)." : "Use: " + _command + " <jogador>" }, true);
                return;
            }
            Responder(quem, Dados(alvo), false);
        }

        private static List<string> Dados(Player p)
        {
            CultureInfo ci = CultureInfo.InvariantCulture;
            SteamPlayer sp = p.channel.owner;
            Vector3 pos = p.transform.position;
            PlayerLife v = p.life;
            List<string> l = new List<string>();
            l.Add(string.Format("[Jogador] {0} (Steam: {1}) - SteamID {2}{3}", sp.playerID.characterName, sp.playerID.playerName,
                sp.playerID.steamID.m_SteamID, sp.isAdmin ? " - admin" : ""));
            l.Add(string.Format(ci, "  Posicao: {0:0.0} {1:0.0} {2:0.0} (giro {3:0}){4}", pos.x, pos.y, pos.z, p.look.yaw, Perto(pos)));
            string estado = "";
            if (v.isDead) estado += " [morto]";
            if (v.isBleeding) estado += " [sangrando]";
            if (v.isBroken) estado += " [perna quebrada]";
            l.Add(string.Format("  Vida {0} | Comida {1} | Agua {2} | Imunidade {3} | Stamina {4}{5}", v.health, v.food, v.water, v.virus, v.stamina, estado));
            int min = (int)((Time.realtimeSinceStartup - sp.joined) / 60f);
            l.Add(string.Format("  XP {0} | Reputacao {1} | Ping {2} ms | Online ha {3} min", p.skills.experience, p.skills.reputation, (int)(sp.ping * 1000f), min));
            InteractableVehicle veh = p.movement.getVehicle();
            ItemAsset item = p.equipment.asset;
            l.Add("  Segurando: " + (item != null ? item.itemName : "nada") + " | Veiculo: " + (veh != null && veh.asset != null ? veh.asset.vehicleName : "nenhum"));
            return l;
        }

        // Local nomeado mais proximo do mapa (cidade, base...), se houver
        private static string Perto(Vector3 pos)
        {
            try
            {
                string melhor = null;
                float dist = float.MaxValue;
                foreach (LocationDevkitNode n in LocationDevkitNodeSystem.Get().GetAllNodes())
                {
                    if (n == null || string.IsNullOrEmpty(n.locationName)) continue;
                    float d = (n.transform.position - pos).magnitude;
                    if (d < dist) { dist = d; melhor = n.locationName; }
                }
                return melhor == null ? "" : string.Format(CultureInfo.InvariantCulture, " - perto de {0} ({1:0} m)", melhor, dist);
            }
            catch (Exception) { return ""; }
        }

        private static void Responder(CSteamID quem, List<string> linhas, bool erro)
        {
            foreach (string s in linhas)
            {
                if (erro) CommandWindow.LogWarning(s); else CommandWindow.Log(s);
                if (quem != CSteamID.Nil && PlayerTool.getPlayer(quem) != null) ChatManager.say(quem, s.Trim(), erro ? Color.red : Color.cyan);
            }
        }
    }
}
