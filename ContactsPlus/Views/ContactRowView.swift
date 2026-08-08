import SwiftUI

struct ContactRowView: View {
    let person: Person
    let density: DensityLevel

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: DensityLevel.Layout.avatarGap) {
            AvatarView(person: person, size: density.avatarSize)

            VStack(alignment: .leading, spacing: density.lineSpacing) {
                Text(person.displayName)
                    .font(density.nameFont)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Each line is simply omitted when the contact lacks the field.
                if density.showsCompany, let company = person.companyLine {
                    Text(company)
                        .font(density.detailFont)
                        // A company guessed from an email domain is dimmer, so
                        // a guess never reads as something the user entered.
                        .foregroundStyle(person.isCompanyInferred ? .tertiary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if density.showsEmail, let email = person.primaryEmail {
                    Text(email)
                        .font(density.detailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DensityLevel.Layout.horizontalPadding)
        .padding(.vertical, density.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1 / displayScale)
                .padding(.leading, density.separatorInset)
        }
    }
}

/// Decoded contact photos, kept between renders.
///
/// `UIImage(data:)` decodes the JPEG on every call, and a row's body re-runs on
/// every frame of a drag — so decoding inline meant re-decoding the same photo
/// around 60 times a second for the row under your finger. Vertical scrolling
/// never showed it because `LazyVStack` builds each row once.
enum ThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(id: String, data: Data?) -> UIImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let data, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: id as NSString)
        return image
    }
}

struct AvatarView: View {
    let person: Person
    let size: CGFloat

    var body: some View {
        Group {
            if let image = ThumbnailCache.image(id: person.id, data: person.thumbnail) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    tint.opacity(0.18)
                    Text(person.initials)
                        .font(.system(size: size * 0.38, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }

    /// Stable per-contact colour so avatars don't reshuffle between launches.
    private var tint: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .brown]
        var hash = 5381
        for byte in person.id.utf8 {
            hash = (hash &* 33) &+ Int(byte)
        }
        return palette[abs(hash) % palette.count]
    }
}
