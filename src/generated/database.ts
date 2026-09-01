export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      alertas: {
        Row: {
          created_at: string
          id: string
          tipo: Database["public"]["Enums"]["tipo_alerta"]
          visita_potencial_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          tipo: Database["public"]["Enums"]["tipo_alerta"]
          visita_potencial_id: string
        }
        Update: {
          created_at?: string
          id?: string
          tipo?: Database["public"]["Enums"]["tipo_alerta"]
          visita_potencial_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "alertas_visita_potencial_id_fkey"
            columns: ["visita_potencial_id"]
            isOneToOne: false
            referencedRelation: "buzon_evaluador"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "alertas_visita_potencial_id_fkey"
            columns: ["visita_potencial_id"]
            isOneToOne: false
            referencedRelation: "visitas_potenciales"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "alertas_visita_potencial_id_fkey"
            columns: ["visita_potencial_id"]
            isOneToOne: false
            referencedRelation: "visitas_potenciales_api"
            referencedColumns: ["id"]
          },
        ]
      }
      calificaciones: {
        Row: {
          created_at: string
          estrellas: number
          evaluador_id: string
          id: string
          solicitud_id: string
        }
        Insert: {
          created_at?: string
          estrellas: number
          evaluador_id: string
          id?: string
          solicitud_id: string
        }
        Update: {
          created_at?: string
          estrellas?: number
          evaluador_id?: string
          id?: string
          solicitud_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "calificaciones_evaluador_id_fkey"
            columns: ["evaluador_id"]
            isOneToOne: false
            referencedRelation: "evaluadores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "calificaciones_solicitud_id_fkey"
            columns: ["solicitud_id"]
            isOneToOne: false
            referencedRelation: "solicitudes"
            referencedColumns: ["id"]
          },
        ]
      }
      evaluadores: {
        Row: {
          auth_user_id: string
          created_at: string
          id: string
          radio_metros: number
          score_confianza: number
          tarjeta_profesional_path: string
          tipo: Database["public"]["Enums"]["tipo_evaluador"]
          transporte_propio: boolean
          ubicacion_base: unknown
          updated_at: string
          ventana: unknown
        }
        Insert: {
          auth_user_id: string
          created_at?: string
          id?: string
          radio_metros: number
          score_confianza?: number
          tarjeta_profesional_path: string
          tipo: Database["public"]["Enums"]["tipo_evaluador"]
          transporte_propio: boolean
          ubicacion_base: unknown
          updated_at?: string
          ventana: unknown
        }
        Update: {
          auth_user_id?: string
          created_at?: string
          id?: string
          radio_metros?: number
          score_confianza?: number
          tarjeta_profesional_path?: string
          tipo?: Database["public"]["Enums"]["tipo_evaluador"]
          transporte_propio?: boolean
          ubicacion_base?: unknown
          updated_at?: string
          ventana?: unknown
        }
        Relationships: [        ]
      }
      campos: {
        Row: {
          cardinalidad: Database["public"]["Enums"]["cardinalidad_campo"]
          codigo: string
          created_at: string
          formulario_id: string
          id: string
          obligatorio: boolean
          opciones: Json | null
          orden: number
          prompt: string
          tipo: Database["public"]["Enums"]["tipo_campo"]
        }
        Insert: {
          cardinalidad?: Database["public"]["Enums"]["cardinalidad_campo"]
          codigo: string
          created_at?: string
          formulario_id: string
          id?: string
          obligatorio?: boolean
          opciones?: Json | null
          orden: number
          prompt: string
          tipo: Database["public"]["Enums"]["tipo_campo"]
        }
        Update: {
          cardinalidad?: Database["public"]["Enums"]["cardinalidad_campo"]
          codigo?: string
          created_at?: string
          formulario_id?: string
          id?: string
          obligatorio?: boolean
          opciones?: Json | null
          orden?: number
          prompt?: string
          tipo?: Database["public"]["Enums"]["tipo_campo"]
        }
        Relationships: []
      }
      coordinadores: {
        Row: {
          auth_user_id: string
          cargo: string | null
          created_at: string
          id: string
          nombre: string
        }
        Insert: {
          auth_user_id: string
          cargo?: string | null
          created_at?: string
          id?: string
          nombre: string
        }
        Update: {
          auth_user_id?: string
          cargo?: string | null
          created_at?: string
          id?: string
          nombre?: string
        }
        Relationships: []
      }
      formularios: {
        Row: {
          codigo: string
          created_at: string
          descripcion: string | null
          estado: Database["public"]["Enums"]["estado_formulario_def"]
          id: string
          nombre: string
          publicado_en: string | null
          version: number
        }
        Insert: {
          codigo: string
          created_at?: string
          descripcion?: string | null
          estado?: Database["public"]["Enums"]["estado_formulario_def"]
          id?: string
          nombre: string
          publicado_en?: string | null
          version?: number
        }
        Update: {
          codigo?: string
          created_at?: string
          descripcion?: string | null
          estado?: Database["public"]["Enums"]["estado_formulario_def"]
          id?: string
          nombre?: string
          publicado_en?: string | null
          version?: number
        }
        Relationships: []
      }
      formularios_diligenciados: {
        Row: {
          autor_id: string | null
          campo_actual_id: string | null
          campo_siguiente_id: string | null
          congelado_en: string | null
          created_at: string
          formulario_id: string
          id: string
          solicitud_id: string | null
          updated_at: string
          visita_realizada_id: string | null
        }
        Insert: {
          autor_id?: string | null
          campo_actual_id?: string | null
          campo_siguiente_id?: string | null
          congelado_en?: string | null
          created_at?: string
          formulario_id: string
          id?: string
          solicitud_id?: string | null
          updated_at?: string
          visita_realizada_id?: string | null
        }
        Update: {
          autor_id?: string | null
          campo_actual_id?: string | null
          campo_siguiente_id?: string | null
          congelado_en?: string | null
          created_at?: string
          formulario_id?: string
          id?: string
          solicitud_id?: string | null
          updated_at?: string
          visita_realizada_id?: string | null
        }
        Relationships: []
      }
      respuestas: {
        Row: {
          campo_id: string
          created_at: string
          formulario_diligenciado_id: string
          id: string
          valor: Json
        }
        Insert: {
          campo_id: string
          created_at?: string
          formulario_diligenciado_id: string
          id?: string
          valor: Json
        }
        Update: {
          campo_id?: string
          created_at?: string
          formulario_diligenciado_id?: string
          id?: string
          valor?: Json
        }
        Relationships: []
      }
      personas: {
        Row: {
          auth_user_id: string
          created_at: string
          id: string
          nombre: string
          telefono: string | null
        }
        Insert: {
          auth_user_id: string
          created_at?: string
          id?: string
          nombre: string
          telefono?: string | null
        }
        Update: {
          auth_user_id?: string
          created_at?: string
          id?: string
          nombre?: string
          telefono?: string | null
        }
        Relationships: []
      }
      solicitudes: {
        Row: {
          created_at: string
          estado: Database["public"]["Enums"]["solicitud_estado"]
          id: string
          solicitante_id: string
          talla: Database["public"]["Enums"]["talla_construccion"]
          ubicacion: unknown
          updated_at: string
          ventana: unknown
        }
        Insert: {
          created_at?: string
          estado: Database["public"]["Enums"]["solicitud_estado"]
          id?: string
          solicitante_id: string
          talla: Database["public"]["Enums"]["talla_construccion"]
          ubicacion: unknown
          updated_at?: string
          ventana: unknown
        }
        Update: {
          created_at?: string
          estado?: Database["public"]["Enums"]["solicitud_estado"]
          id?: string
          solicitante_id?: string
          talla?: Database["public"]["Enums"]["talla_construccion"]
          ubicacion?: unknown
          updated_at?: string
          ventana?: unknown
        }
        Relationships: [
          {
            foreignKeyName: "solicitudes_solicitante_id_fkey"
            columns: ["solicitante_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      visitas_potenciales: {
        Row: {
          causa_cancelacion:
            | Database["public"]["Enums"]["causa_cancelacion"]
            | null
          created_at: string
          estado: Database["public"]["Enums"]["visita_potencial_estado"]
          evaluador_id: string
          id: string
          pin_intentos: number
          pin_verificado_en: string | null
          solicitud_id: string
          updated_at: string
          ventana_propuesta: unknown
        }
        Insert: {
          causa_cancelacion?:
            | Database["public"]["Enums"]["causa_cancelacion"]
            | null
          created_at?: string
          estado: Database["public"]["Enums"]["visita_potencial_estado"]
          evaluador_id: string
          id?: string
          pin_intentos?: number
          pin_verificado_en?: string | null
          solicitud_id: string
          updated_at?: string
          ventana_propuesta: unknown
        }
        Update: {
          causa_cancelacion?:
            | Database["public"]["Enums"]["causa_cancelacion"]
            | null
          created_at?: string
          estado?: Database["public"]["Enums"]["visita_potencial_estado"]
          evaluador_id?: string
          id?: string
          pin_intentos?: number
          pin_verificado_en?: string | null
          solicitud_id?: string
          updated_at?: string
          ventana_propuesta?: unknown
        }
        Relationships: [
          {
            foreignKeyName: "visitas_potenciales_evaluador_id_fkey"
            columns: ["evaluador_id"]
            isOneToOne: false
            referencedRelation: "evaluadores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitas_potenciales_solicitud_id_fkey"
            columns: ["solicitud_id"]
            isOneToOne: false
            referencedRelation: "solicitudes"
            referencedColumns: ["id"]
          },
        ]
      }
      visitas_realizadas: {
        Row: {
          anotaciones: string | null
          concluida_en: string | null
          created_at: string
          evaluador_id: string
          id: string
          resultado: Database["public"]["Enums"]["resultado_evaluacion"] | null
          solicitud_id: string
          visita_potencial_id: string
        }
        Insert: {
          anotaciones?: string | null
          concluida_en?: string | null
          created_at?: string
          evaluador_id: string
          id?: string
          resultado?: Database["public"]["Enums"]["resultado_evaluacion"] | null
          solicitud_id: string
          visita_potencial_id: string
        }
        Update: {
          anotaciones?: string | null
          concluida_en?: string | null
          created_at?: string
          evaluador_id?: string
          id?: string
          resultado?: Database["public"]["Enums"]["resultado_evaluacion"] | null
          solicitud_id?: string
          visita_potencial_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "visitas_realizadas_evaluador_id_fkey"
            columns: ["evaluador_id"]
            isOneToOne: false
            referencedRelation: "evaluadores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitas_realizadas_solicitud_id_fkey"
            columns: ["solicitud_id"]
            isOneToOne: false
            referencedRelation: "solicitudes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitas_realizadas_visita_potencial_id_fkey"
            columns: ["visita_potencial_id"]
            isOneToOne: true
            referencedRelation: "buzon_evaluador"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitas_realizadas_visita_potencial_id_fkey"
            columns: ["visita_potencial_id"]
            isOneToOne: true
            referencedRelation: "visitas_potenciales"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitas_realizadas_visita_potencial_id_fkey"
            columns: ["visita_potencial_id"]
            isOneToOne: true
            referencedRelation: "visitas_potenciales_api"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      evidencias: {
        Row: {
          campo_formulario: string | null
          captured_at: string | null
          id: string | null
          storage_path: string | null
          visita_realizada_id: string | null
        }
        Relationships: []
      }
      buzon_evaluador: {
        Row: {
          created_at: string | null
          id: string | null
          solicitud_id: string | null
          talla: Database["public"]["Enums"]["talla_construccion"] | null
          ubicacion: unknown
          ventana_propuesta: unknown
        }
        Relationships: [
          {
            foreignKeyName: "visitas_potenciales_solicitud_id_fkey"
            columns: ["solicitud_id"]
            isOneToOne: false
            referencedRelation: "solicitudes"
            referencedColumns: ["id"]
          },
        ]
      }
      visitas_potenciales_api: {
        Row: {
          causa_cancelacion:
            | Database["public"]["Enums"]["causa_cancelacion"]
            | null
          created_at: string | null
          estado: Database["public"]["Enums"]["visita_potencial_estado"] | null
          evaluador_id: string | null
          id: string | null
          pin_intentos: number | null
          pin_verificado_en: string | null
          solicitud_id: string | null
          updated_at: string | null
          ventana_propuesta: unknown
        }
        Insert: {
          causa_cancelacion?:
            | Database["public"]["Enums"]["causa_cancelacion"]
            | null
          created_at?: string | null
          estado?: Database["public"]["Enums"]["visita_potencial_estado"] | null
          evaluador_id?: string | null
          id?: string | null
          pin_intentos?: number | null
          pin_verificado_en?: string | null
          solicitud_id?: string | null
          updated_at?: string | null
          ventana_propuesta?: unknown
        }
        Update: {
          causa_cancelacion?:
            | Database["public"]["Enums"]["causa_cancelacion"]
            | null
          created_at?: string | null
          estado?: Database["public"]["Enums"]["visita_potencial_estado"] | null
          evaluador_id?: string | null
          id?: string | null
          pin_intentos?: number | null
          pin_verificado_en?: string | null
          solicitud_id?: string | null
          updated_at?: string | null
          ventana_propuesta?: unknown
        }
        Relationships: [
          {
            foreignKeyName: "visitas_potenciales_evaluador_id_fkey"
            columns: ["evaluador_id"]
            isOneToOne: false
            referencedRelation: "evaluadores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitas_potenciales_solicitud_id_fkey"
            columns: ["solicitud_id"]
            isOneToOne: false
            referencedRelation: "solicitudes"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      aceptar_visita: { Args: { visita_id: string }; Returns: Json }
      iniciar_formulario: {
        Args: {
          codigo_formulario?: string | undefined
          solicitud_id?: string | undefined
          version?: number | undefined
          visita_realizada_id?: string | undefined
        }
        Returns: Json
      }
      crear_formulario: {
        Args: {
          codigo: string
          descripcion?: string | undefined
          nombre: string
        }
        Returns: Json
      }
      publicar_formulario: {
        Args: {
          formulario_id: string
        }
        Returns: Json
      }
      archivar_formulario: {
        Args: {
          formulario_id: string
        }
        Returns: Json
      }
      crear_nueva_version_formulario: {
        Args: {
          codigo: string
        }
        Returns: Json
      }
      agregar_campo: {
        Args: {
          cardinalidad?:
            | Database["public"]["Enums"]["cardinalidad_campo"]
            | undefined
          codigo: string
          formulario_id: string
          obligatorio?: boolean | undefined
          opciones?: Json | undefined
          orden: number
          prompt: string
          tipo: Database["public"]["Enums"]["tipo_campo"]
        }
        Returns: Json
      }
      registrar_coordinador: {
        Args: {
          cargo?: string | undefined
          nombre: string
        }
        Returns: {
          auth_user_id: string
          cargo: string | null
          created_at: string
          id: string
          nombre: string
        }
      }
      estado_formulario: {
        Args: { formulario_diligenciado_id: string }
        Returns: Json
      }
      responder_campo: {
        Args: {
          formulario_diligenciado_id: string
          campo_id: string
          valor: Json
          respuesta_id?: string | undefined
        }
        Returns: Json
      }
      respuestas_formulario: {
        Args: { formulario_diligenciado_id: string }
        Returns: Json
      }
      commit_formulario: {
        Args: { formulario_diligenciado_id: string }
        Returns: Json
      }
      calificar_evaluador: {
        Args: { estrellas: number; evaluador_id: string; solicitud_id: string }
        Returns: {
          created_at: string
          estrellas: number
          evaluador_id: string
          id: string
          solicitud_id: string
        }
        SetofOptions: {
          from: "*"
          to: "calificaciones"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      concluir_visita: {
        Args: {
          anotaciones: string
          resultado: Database["public"]["Enums"]["resultado_evaluacion"]
          visita_realizada_id: string
        }
        Returns: {
          anotaciones: string | null
          concluida_en: string | null
          created_at: string
          evaluador_id: string
          id: string
          resultado: Database["public"]["Enums"]["resultado_evaluacion"] | null
          solicitud_id: string
          visita_potencial_id: string
        }
        SetofOptions: {
          from: "*"
          to: "visitas_realizadas"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      crear_solicitud: {
        Args: {
          lat: number
          lng: number
          talla: Database["public"]["Enums"]["talla_construccion"]
          ventana: unknown
        }
        Returns: {
          created_at: string
          estado: Database["public"]["Enums"]["solicitud_estado"]
          id: string
          solicitante_id: string
          talla: Database["public"]["Enums"]["talla_construccion"]
          ubicacion: unknown
          updated_at: string
          ventana: unknown
        }
        SetofOptions: {
          from: "*"
          to: "solicitudes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      generar_visitas_potenciales: { Args: never; Returns: number }
      jwt_rol: { Args: never; Returns: string }
      marcar_no_encontrada: {
        Args: { visita_realizada_id: string }
        Returns: undefined
      }
      rechazar_visita: {
        Args: { visita_id: string }
        Returns: {
          causa_cancelacion:
            | Database["public"]["Enums"]["causa_cancelacion"]
            | null
          created_at: string
          estado: Database["public"]["Enums"]["visita_potencial_estado"]
          evaluador_id: string
          id: string
          pin_intentos: number
          pin_verificado_en: string | null
          solicitud_id: string
          updated_at: string
          ventana_propuesta: unknown
        }
        SetofOptions: {
          from: "*"
          to: "visitas_potenciales"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      regenerar_pin: { Args: { visita_id: string }; Returns: Json }
      registrar_evaluador: {
        Args: {
          lat: number
          lng: number
          radio_metros: number
          tarjeta_profesional_path: string
          tipo: Database["public"]["Enums"]["tipo_evaluador"]
          transporte_propio: boolean
          ventana: unknown
        }
        Returns: {
          auth_user_id: string
          created_at: string
          id: string
          radio_metros: number
          score_confianza: number
          tarjeta_profesional_path: string
          tipo: Database["public"]["Enums"]["tipo_evaluador"]
          transporte_propio: boolean
          ubicacion_base: unknown
          updated_at: string
          ventana: unknown
        }
        SetofOptions: {
          from: "*"
          to: "evaluadores"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      registrar_persona: {
        Args: { nombre: string; telefono: string }
        Returns: {
          auth_user_id: string
          created_at: string
          id: string
          nombre: string
          telefono: string | null
        }
        SetofOptions: {
          from: "*"
          to: "personas"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      verificar_pin: { Args: { pin: string; visita_id: string }; Returns: Json }
    }
    Enums: {
      estado_formulario_def: "borrador" | "publicado" | "archivado"
      cardinalidad_campo: "uno" | "muchos"
      tipo_campo:
        | "texto"
        | "likert"
        | "opcion"
        | "imagen"
        | "geolocalizacion"
      causa_cancelacion:
        | "pin_fallido"
        | "evaluador"
        | "solicitante"
        | "tomada_por_otro"
      resultado_evaluacion: "habitable" | "restringido" | "insegura"
      solicitud_estado:
        | "creada"
        | "visita_pendiente"
        | "en_evaluacion"
        | "evaluacion_fallida"
        | "evaluacion_parcial"
        | "evaluada"
      talla_construccion: "xs" | "s" | "m" | "l" | "xl"
      tipo_alerta: "pin_incorrecto"
      tipo_evaluador: "voluntario" | "oficial"
      visita_potencial_estado: "creada" | "aceptada" | "rechazada" | "cancelada"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      causa_cancelacion: [
        "pin_fallido",
        "evaluador",
        "solicitante",
        "tomada_por_otro",
      ],
      resultado_evaluacion: ["habitable", "restringido", "insegura"],
      solicitud_estado: [
        "creada",
        "visita_pendiente",
        "en_evaluacion",
        "evaluacion_fallida",
        "evaluacion_parcial",
        "evaluada",
      ],
      talla_construccion: ["xs", "s", "m", "l", "xl"],
      tipo_alerta: ["pin_incorrecto"],
      tipo_evaluador: ["voluntario", "oficial"],
      visita_potencial_estado: ["creada", "aceptada", "rechazada", "cancelada"],
      estado_formulario_def: ["borrador", "publicado", "archivado"],
      cardinalidad_campo: ["uno", "muchos"],
      tipo_campo: [
        "texto",
        "likert",
        "opcion",
        "imagen",
        "geolocalizacion",
      ],
    },
  },
} as const

