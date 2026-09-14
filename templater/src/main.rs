//! Renders a MiniJinja template against a JSON context file and writes the
//! result to stdout.
//!
//! Printing an undefined value is a hard error. MiniJinja's default `Lenient`
//! behaviour renders a missing key on an existing object as an empty string
//! with a success exit code, which silently produces broken courier config --
//! `TLS_CERTFILE={{ mta.tls_certfile }}` with the key absent yields
//! `TLS_CERTFILE=` and courier starts with an empty certificate path.
//!
//! This is enforced with a custom formatter rather than
//! `UndefinedBehavior::Strict`, because Strict rejects the lookup itself and so
//! breaks `{{ x.y | default("z") }}` as well -- under Strict there is no
//! working way to express an optional value, not even `is defined`. A formatter
//! sees the value only after filters have run, so an explicit `default()` still
//! works while a bare undefined does not.
//!
//! `UndefinedBehavior::Chainable` is set so that a missing intermediate
//! (`{{ a.b.c }}` where `a` is absent) reaches the formatter and produces the
//! same clear error, and so that `{{ a.b | default("z") }}` works for nested
//! paths too.
use std::error::Error;
use std::fs;
use std::path::PathBuf;

use argh::FromArgs;
use minijinja::{escape_formatter, Environment, UndefinedBehavior};

/// A small application that renders a MiniJinja template.
#[derive(FromArgs)]
struct Cli {
    /// the path to a JSON file with the context
    #[argh(option, short = 'c', long = "context")]
    context: PathBuf,

    /// the path to a template file that should be rendered
    #[argh(option, short = 't', long = "template")]
    template: PathBuf,
}

fn build_environment<'a>() -> Environment<'a> {
    let mut env = Environment::new();
    env.set_undefined_behavior(UndefinedBehavior::Chainable);
    env.set_formatter(|out, state, value| {
        if value.is_undefined() {
            return Err(minijinja::Error::new(
                minijinja::ErrorKind::UndefinedError,
                "refusing to render an undefined value as an empty string; \
                 add the key to the context, or write an explicit \
                 `| default(\"...\")` if it is genuinely optional",
            ));
        }
        escape_formatter(out, state, value)
    });
    env
}

fn execute() -> Result<(), Box<dyn Error>> {
    let cli: Cli = argh::from_env();

    let mut env = build_environment();

    let source = fs::read_to_string(&cli.template)
        .map_err(|e| format!("{}: {}", cli.template.display(), e))?;
    let name = cli
        .template
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or_else(|| format!("{}: not a usable template file name", cli.template.display()))?;
    env.add_template(name, &source)?;

    let raw = fs::read(&cli.context).map_err(|e| format!("{}: {}", cli.context.display(), e))?;
    let ctx: serde_json::Value =
        serde_json::from_slice(&raw).map_err(|e| format!("{}: {}", cli.context.display(), e))?;

    let tmpl = env.get_template(name)?;
    print!("{}", tmpl.render(&ctx)?);

    Ok(())
}

fn main() {
    if let Err(err) = execute() {
        eprintln!("render-template: {}", err);
        // MiniJinja puts the template name and line in the source chain, so
        // surface all of it rather than just the top message.
        let mut cause = err.source();
        while let Some(e) = cause {
            eprintln!("  caused by: {}", e);
            cause = e.source();
        }
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::build_environment;

    fn render(template: &str, ctx: serde_json::Value) -> Result<String, String> {
        let mut env = build_environment();
        env.add_template("t", template).map_err(|e| e.to_string())?;
        env.get_template("t")
            .map_err(|e| e.to_string())?
            .render(&ctx)
            .map_err(|e| e.to_string())
    }

    fn ctx() -> serde_json::Value {
        serde_json::json!({ "mta": { "dns_name": "mail.example.com" } })
    }

    #[test]
    fn renders_a_present_value() {
        assert_eq!(render("{{ mta.dns_name }}", ctx()).unwrap(), "mail.example.com");
    }

    #[test]
    fn missing_key_on_existing_object_is_an_error() {
        // The regression this whole change exists for: previously rendered as
        // "" with a zero exit code.
        assert!(render("{{ mta.nope }}", ctx()).is_err());
    }

    #[test]
    fn missing_top_level_variable_is_an_error() {
        assert!(render("{{ nope }}", ctx()).is_err());
    }

    #[test]
    fn missing_intermediate_is_an_error() {
        assert!(render("{{ nope.deeper }}", ctx()).is_err());
    }

    #[test]
    fn explicit_default_still_works() {
        // Must keep working: configmap.yaml relies on this heavily, and it is
        // what UndefinedBehavior::Strict would have broken.
        assert_eq!(
            render(r#"{{ mta.nope | default("fallback") }}"#, ctx()).unwrap(),
            "fallback"
        );
    }

    #[test]
    fn explicit_default_works_for_nested_paths() {
        assert_eq!(
            render(r#"{{ nope.deeper | default("fallback") }}"#, ctx()).unwrap(),
            "fallback"
        );
    }

    #[test]
    fn default_does_not_mask_a_present_value() {
        assert_eq!(
            render(r#"{{ mta.dns_name | default("fallback") }}"#, ctx()).unwrap(),
            "mail.example.com"
        );
    }

    #[test]
    fn iterating_a_present_list_works() {
        let c = serde_json::json!({ "mta": { "accept_mail_for": ["a.com", "b.com"] } });
        assert_eq!(
            render("{% for d in mta.accept_mail_for %}{{ d }},{% endfor %}", c).unwrap(),
            "a.com,b.com,"
        );
    }
}
