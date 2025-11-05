import { Button } from "@/components/ui/button";
import { hasSupabase, supabaseClient } from "@/lib/supabaseClient";

export function SupabaseGoogleButton({ redirectPath = "/signin" }: { redirectPath?: string }) {
  if (!hasSupabase) return null;
  const onClick = async () => {
    const redirectTo = `${window.location.origin}${redirectPath}`;
    await supabaseClient.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo },
    });
  };
  return (
    <Button onClick={onClick} variant="outline" className="w-full">
      Continue with Google
    </Button>
  );
}
